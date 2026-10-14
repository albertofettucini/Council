#!/usr/bin/env python3
"""Turn one recorded Council session into the bundled example council
(Council/Resources/ExampleCouncil.json).

The example is a real, unedited session that ships inside the app and opens read-only. This script
never edits answer text. It refuses anything that would make a misleading or private example:

  - more than one round (or none);
  - an attachment (hadAttachment / attachedDocument) or a guest answer;
  - any journal, reminder or Engram field;
  - missing peer reviews, divergence, divergence score, synthesis or rebuttals;
  - a missing outlier / outlierSeatID (no dissent card).

It gives the session and its round fresh ids, drops the conversation history, wraps it with what
the session file doesn't record (each seat's provider and model, who synthesized, the chair), runs
the release secret scan over the result, and prints the label the app will show.

Two ways to say what the seats were:

  Explicit (seat setup known from the recording):
    python3 -I scripts/make-example-council.py --session /path/to/session.json \\
      --seat 0=Claude:claude-sonnet-4-6 --seat 1=GPT:gpt-5.4-mini --seat 2=Ollama:llama3.2 \\
      --synthesizer Claude --app-version 1.3.0 --recorded-at 2026-10-14T11:56:51Z

  From the installed app (reads the session and the seat setup from Council's container; macOS
  asks once to allow access to another app's data):
    python3 -I scripts/make-example-council.py --container-session <session-uuid> --app-version 1.3.0

Personas: container mode compares each seat's prompt with the default personas. In explicit mode
pass --personas default (or custom) if you know; otherwise the example records them as unchecked.
"""

import argparse
import json
import plistlib
import subprocess
import sys
import uuid
from pathlib import Path

SCHEMA = "council.example.v1"
GUEST_SEAT_ID = "99"
BUNDLE_ID = "com.joseph.Council"
REPO = Path(__file__).resolve().parent.parent
DEFAULT_OUT = REPO / "Council" / "Resources" / "ExampleCouncil.json"
SECRET_PATTERNS = Path.home() / ".config" / "council-release" / "secret-patterns.txt"
CONTAINER_DATA = Path.home() / "Library" / "Containers" / BUNDLE_ID / "Data" / "Library"

JOURNAL_FIELDS = ("decision", "decisionAt", "outcome", "outcomeAt", "remindAt",
                  "engramMemoryID", "engramRememberedAt")

# LLMProvider.rawValue -> panelName (CouncilKit/LLMProvider.swift).
PANEL_NAMES = {
    "claude": "Claude", "openAI": "GPT", "gemini": "Gemini", "deepSeek": "DeepSeek", "grok": "Grok",
    "mistral": "Mistral", "perplexity": "Perplexity", "openRouter": "OpenRouter", "ollama": "Ollama",
    "foundationModels": "Apple", "custom1": "Custom", "custom2": "Custom",
}

# CouncilStore.personaAnalyst / personaPractitioner / personaSkeptic, by seat id. They are Swift
# multi-line literals with line continuations, so each is ONE line of text.
DEFAULT_PERSONAS = {
    0: ("You are the analyst on a council of advisors. Reason from first principles: name the core "
        "variables, state your assumptions, and show the logic that leads to your answer. Give a "
        "complete, well-structured answer to the user's question, and be honest about tradeoffs and "
        "uncertainty — if the real answer is \"it depends,\" say exactly what it depends on. Don't hedge "
        "to sound agreeable. Be concise and in your own voice."),
    1: ("You are the practitioner on a council of advisors. Answer from real-world experience: what "
        "actually happens in practice, the second-order effects, the practical constraints, and what "
        "most people get wrong. Give a complete, decisive answer to the user's question, grounded in how "
        "this plays out for real, and prefer concrete specifics over abstractions. Be concise and in "
        "your own voice; no flattery."),
    2: ("You are the skeptic on a council of advisors. Challenge the easy answer: question the framing, "
        "surface the strongest counter-case, and name the risks and failure modes the others will likely "
        "miss. Still give a complete answer to the user's question — take the position you actually find "
        "most defensible, even if it's unpopular — but make the costs and downsides explicit. Be specific "
        "and intellectually honest, never contrarian just for show. Concise, in your own voice."),
}


class Refusal(Exception):
    pass


def nonempty(value):
    if value is None:
        return False
    if isinstance(value, (str, dict, list)):
        return len(value) > 0
    return True


def nonempty_texts(d):
    return isinstance(d, dict) and any(isinstance(v, str) and v.strip() for v in d.values())


def check_session(session):
    """Every reason this session can't be the example, as a list of strings (empty = fine)."""
    problems = []
    rounds = session.get("rounds") or []
    if len(rounds) != 1:
        problems.append(f"needs exactly one round, has {len(rounds)}")
    for field in JOURNAL_FIELDS:
        if nonempty(session.get(field)):
            problems.append(f"journal/reminder/Engram field '{field}' is set")
    if not rounds:
        return problems
    r = rounds[0]
    if r.get("hadAttachment"):
        problems.append("the round had an attachment (hadAttachment)")
    if nonempty(r.get("attachedDocument")):
        problems.append("the round stores an attached document")
    answers = r.get("answers") or {}
    if nonempty(answers.get(GUEST_SEAT_ID)):
        problems.append("the round has a guest answer")
    real = sorted(k for k, v in answers.items() if k != GUEST_SEAT_ID and isinstance(v, str) and v.strip())
    if len(real) < 2:
        problems.append(f"needs at least two advisor answers, has {len(real)}")
    if not nonempty_texts(r.get("peerReviews")):
        problems.append("peer reviews are missing")
    if not nonempty(r.get("divergence")):
        problems.append("divergence is missing")
    if r.get("divergenceScore") is None:
        problems.append("divergence score is missing")
    if not nonempty(r.get("synthesis")):
        problems.append("synthesis is missing")
    if not nonempty_texts(r.get("rebuttals")):
        problems.append("rebuttals (the debate) are missing")
    if not nonempty(r.get("outlier")):
        problems.append("no outlier was named (there would be no dissent card)")
    sid = r.get("outlierSeatID")
    if sid is None:
        problems.append("outlierSeatID is missing")
    elif str(sid) not in real:
        problems.append(f"outlierSeatID {sid} has no answer")
    return problems


def parse_seat_arg(raw):
    """'0=Claude:claude-sonnet-4-6' -> (0, 'Claude', 'claude-sonnet-4-6')."""
    try:
        sid, rest = raw.split("=", 1)
        provider, model = rest.split(":", 1)
        return int(sid), provider.strip(), model.strip()
    except ValueError:
        raise Refusal(f"--seat '{raw}' should look like 0=Claude:claude-sonnet-4-6")


def seats_from_container():
    """Seats, synthesizer and chair from the installed app's preferences."""
    plist = CONTAINER_DATA / "Preferences" / f"{BUNDLE_ID}.plist"
    try:
        with open(plist, "rb") as f:
            prefs = plistlib.load(f)
    except OSError as e:
        raise Refusal(f"can't read Council's preferences ({e.strerror}); allow the data-access prompt and retry")
    raw = prefs.get("council.seats.v7")
    if not isinstance(raw, (bytes, bytearray)):
        raise Refusal("Council's preferences have no saved seats")
    seats = json.loads(raw)
    out = []
    for s in seats:
        provider = s.get("provider")
        if not provider:
            continue
        prompt = (s.get("systemPrompt") or "").strip()
        default = DEFAULT_PERSONAS.get(s["id"])
        out.append({"seatID": s["id"], "provider": PANEL_NAMES.get(provider, provider),
                    "model": s.get("model") or "", "defaultPersona": bool(default) and prompt == default})
    chair = None
    chair_raw = prefs.get("council.chairSeat")
    if isinstance(chair_raw, (bytes, bytearray)):
        c = json.loads(chair_raw)
        if c.get("provider"):
            chair = PANEL_NAMES.get(c["provider"], c["provider"])
    synth_id = prefs.get("council.synthesizerSeat", 0)
    synth = next((s["provider"] for s in out if s["seatID"] == synth_id), out[0]["provider"] if out else None)
    if chair:
        synth = chair
    return out, synth, chair


def secret_scan(path):
    if not SECRET_PATTERNS.exists():
        raise Refusal(f"secret-pattern file not found at ~/{SECRET_PATTERNS.relative_to(Path.home())}")
    hit = subprocess.run(["grep", "-nIE", "-f", str(SECRET_PATTERNS), str(path)],
                         capture_output=True, text=True)
    if hit.returncode == 0:
        raise Refusal("the secret scan matched the output (lines withheld on purpose)")
    if hit.returncode != 1:
        raise Refusal(f"the secret scan failed to run: {hit.stderr.strip()}")


def label(seats, recorded_at):
    day = f"{int(recorded_at[8:10])} {MONTHS[int(recorded_at[5:7]) - 1]} {recorded_at[:4]}"
    parts = []
    for s in sorted(seats, key=lambda s: s["seatID"]):
        detail = s["model"]
        if s.get("defaultPersona") is False:
            detail = f"{detail}, custom persona" if detail else "custom persona"
        parts.append(f"{s['provider']} ({detail})" if detail else s["provider"])
    return f"Recorded {day} with {', '.join(parts)}"


MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument("--session", type=Path, help="a session .json file")
    src.add_argument("--container-session", metavar="UUID",
                     help="a session id in the installed app's container (seats are read from its preferences)")
    ap.add_argument("--seat", action="append", default=[], metavar="ID=PROVIDER:MODEL",
                    help="explicit seat setup, one per answering seat")
    ap.add_argument("--synthesizer", help="who wrote the divergence and synthesis (panel name)")
    ap.add_argument("--chair", help="the neutral chair, if one was seated (panel name)")
    ap.add_argument("--personas", choices=["default", "custom", "unknown"], default="unknown",
                    help="explicit mode only: were the default personas in use?")
    ap.add_argument("--app-version", help="the Council version the session was recorded with")
    ap.add_argument("--recorded-at", help="ISO 8601 UTC time of the recording (default: the session's updatedAt)")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = ap.parse_args()

    if args.container_session:
        try:
            uuid.UUID(args.container_session)
        except ValueError:
            raise Refusal("--container-session must be a session UUID")
        session_path = (CONTAINER_DATA / "Application Support" / "Council" / "Sessions"
                        / f"{args.container_session.upper()}.json")
    else:
        session_path = args.session
    try:
        session = json.loads(session_path.read_text(encoding="utf-8"))
    except OSError as e:
        raise Refusal(f"can't read the session ({e.strerror})")

    problems = check_session(session)
    if problems:
        raise Refusal("this session can't be the example:\n  - " + "\n  - ".join(problems))
    rnd = session["rounds"][0]

    if args.container_session and not args.seat:
        seats, synthesizer, chair = seats_from_container()
        synthesizer = args.synthesizer or synthesizer
        chair = args.chair or chair
    else:
        if not args.seat:
            raise Refusal("give the seat setup with --seat (or use --container-session)")
        persona = {"default": True, "custom": False, "unknown": None}[args.personas]
        seats = []
        for raw in args.seat:
            sid, provider, model = parse_seat_arg(raw)
            seat = {"seatID": sid, "provider": provider, "model": model}
            if persona is not None:
                seat["defaultPersona"] = persona
            seats.append(seat)
        synthesizer, chair = args.synthesizer, args.chair

    # The label must name exactly the providers the session recorded for each answer.
    recorded = {k: v for k, v in (rnd.get("answerProviders") or {}).items() if k != GUEST_SEAT_ID}
    answered = {k for k, v in rnd["answers"].items() if k != GUEST_SEAT_ID and isinstance(v, str) and v.strip()}
    by_id = {str(s["seatID"]): s for s in seats}
    if len(by_id) != len(seats):
        raise Refusal("a seat id is given twice")
    mismatch = []
    for sid in sorted(answered):
        s = by_id.get(sid)
        if s is None:
            mismatch.append(f"seat {sid} answered but has no seat setup")
        elif recorded.get(sid) != s["provider"]:
            mismatch.append(f"seat {sid}: the session says {recorded.get(sid)!r}, the setup says {s['provider']!r}")
    for sid in sorted(set(by_id) - answered):
        mismatch.append(f"seat {sid} has a setup but no answer")
    if mismatch:
        raise Refusal("the seat setup doesn't match the session:\n  - " + "\n  - ".join(mismatch))
    if not synthesizer:
        raise Refusal("say who synthesized with --synthesizer")

    # Fresh ids, no history: nothing ties the bundled copy to the session file it came from.
    session["id"] = str(uuid.uuid4()).upper()
    rnd["id"] = str(uuid.uuid4()).upper()
    session["history"] = {}

    recorded_at = args.recorded_at or session.get("updatedAt") or session.get("createdAt")
    wrapper = {
        "schema": SCHEMA,
        "recordedAt": recorded_at,
        "seats": sorted(seats, key=lambda s: s["seatID"]),
        "synthesizer": synthesizer,
        "session": session,
    }
    if args.app_version:
        wrapper["appVersion"] = args.app_version
    if chair:
        wrapper["chair"] = chair

    out = args.out
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(wrapper, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")
    try:
        secret_scan(tmp)
    except Refusal:
        tmp.unlink()
        raise
    tmp.replace(out)

    print(f"wrote {out.relative_to(REPO) if out.is_relative_to(REPO) else out}")
    print(f"question:    {rnd.get('question')}")
    print(f"label:       {label(seats, recorded_at)}")
    print(f"synthesizer: {synthesizer}" + (f"  (chair: {chair})" if chair else ""))
    print(f"outlier:     {rnd.get('outlier')} (seat {rnd.get('outlierSeatID')}), "
          f"agreement {rnd.get('divergenceScore')}, camps {rnd.get('divergenceCamps')}")
    unchecked = [s["seatID"] for s in seats if s.get("defaultPersona") is None]
    if unchecked:
        print(f"note: personas not checked for seat(s) {unchecked}; pass --personas default|custom if you know")
    print("Compare the label and the synthesizer with what the app showed for this session.")


if __name__ == "__main__":
    try:
        main()
    except Refusal as e:
        print(f"refused: {e}", file=sys.stderr)
        sys.exit(1)
