import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "helper"))
from screen_status import classify, present


class ScreenStatusTests(unittest.TestCase):
    def test_idle_prompts_of_each_cli(self):
        self.assertEqual(classify("older ❯ command\n\n❯\nOpus"), ("idle", None))
        self.assertEqual(classify("› Ask Codex to do anything\nGPT-6"), ("idle", None))
        self.assertEqual(classify("→ Add a follow-up\nnotch_control"), ("idle", None))

    def test_a_finished_turn_waiting_for_the_next_prompt_is_a_result_not_a_decision(self):
        self.assertEqual(classify("Brewed for 10s · done 2:11\n❯\nOpus"), ("idle", "result"))
        self.assertEqual(classify("Worked for 2s\n› Ask Codex to do anything"), ("idle", "result"))
        self.assertEqual(classify("Esc to cancel\n❯"), ("idle", None))

    def test_working_markers_win_over_the_composer_placeholder(self):
        screen = "→ Add a follow-up\nRunning  2.88k tokens\nctrl+c to stop"
        self.assertEqual(classify(screen), ("working", None))
        self.assertEqual(classify("• Working (1s • esc to interrupt)\n› Ask Codex to do anything"), ("working", None))

    def test_approval_is_waiting_even_when_a_prompt_mark_is_on_screen(self):
        screen = "Do you want to proceed?\n❯ 1. Yes\n2. Yes, and don't ask again"
        self.assertEqual(classify(screen), ("waiting", "approval"))

    def test_old_prompt_above_the_tail_does_not_count_as_idle(self):
        lines = ["❯ previous command"] + ["output"] * 20 + ["still thinking about it"]
        self.assertIsNone(classify("\n".join(lines)))

    def test_unrecognized_screen_does_not_invent_a_state(self):
        self.assertIsNone(classify("just a shell\n$"))

    def test_a_decision_quoted_in_the_transcript_is_not_a_decision(self):
        transcript = "\n".join([
            "the phrase do you want to proceed is only mentioned here",
            "approve this is also just text",
            "more output",
            "more output",
            "→ Add a follow-up",
            "notch_control",
        ])
        self.assertEqual(classify(transcript), ("idle", None))

    def test_green_until_the_terminal_is_focused_then_idle(self):
        self.assertEqual(present(("idle", "result"), ("working", None), focused=False), ("idle", "result"))
        self.assertEqual(present(("idle", "result"), ("working", None), focused=True), ("idle", None))
        self.assertIsNone(present(("idle", "result"), ("idle", "result"), focused=False))
        self.assertEqual(present(("idle", "result"), ("idle", "result"), focused=True), ("idle", None))
        self.assertIsNone(present(("idle", "result"), ("idle", None), focused=False))

    def test_the_green_is_held_when_the_screen_carries_no_end_of_turn_marker(self):
        self.assertIsNone(present(("idle", None), ("idle", "result"), focused=False))
        self.assertEqual(present(("idle", None), ("idle", "result"), focused=True), ("idle", None))
        self.assertIsNone(present(("idle", None), ("idle", None), focused=False))
        self.assertEqual(present(("idle", None), ("working", None), focused=False), ("idle", "result"))


RULE = "─" * 60


def screen(*lines):
    return "\n".join(lines)


def composer(placeholder="", status=("  Haiku 4.5 · notch_control", "  ⏸ manual mode on · ← 1 agent")):
    return [RULE, ("❯ " + placeholder).rstrip(), RULE, *status]


def claude(*lines):
    return classify(screen(*lines), "claude")


class ClaudeCodeScreenTests(unittest.TestCase):
    """Screens captured from Claude Code 2.1.289 in iTerm2, reduced to the interface lines."""

    def test_spinner_above_the_empty_composer_is_working(self):
        self.assertEqual(claude(
            "❯ do the thing", "  Running 1 shell command…", "· Hashing… (1s · thinking)",
            "                You've used 98% of your weekly limit · resets 4pm · Run /usage-credits", *composer()),
            ("working", None))
        self.assertEqual(claude(
            "✻ Deciphering… (33s · ↓ 3.2k tokens)", "  ⎿  Tip: Use /memory to view and manage Claude memory", "",
            *composer(status=("Sonnet 5.5 · 92% left · notch_control · 5h 2% · 7d 98%",
                              "  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent"))),
            ("working", None))
        self.assertEqual(claude("✢ Scampering… (1m 5s · ↑ 1.2k tokens)", *composer()), ("working", None))

    def test_spinner_while_a_hook_runs_is_still_working(self):
        # With user hooks configured, Claude Code shows the hook where the elapsed time normally is.
        self.assertEqual(claude(
            "⏺ Updated plan", "  ⎿  /plan to preview", "· Considering… (running PreToolUse hook · 7s · ↓ 619 tokens)",
            "                You've used 98% of your weekly limit · resets 4pm · Run /usage-credits", *composer()),
            ("working", None))

    def test_a_spinner_left_in_older_output_does_not_outlast_the_finished_turn(self):
        self.assertEqual(claude("· Loading… (docs)", "⏺ Done.", "✻ Worked for 3s · done 2:48", *composer()), ("idle", "result"))

    def test_a_finished_turn_is_a_result_whatever_verb_claude_picked(self):
        for verb in ("Baked", "Brewed", "Churned", "Cogitated", "Cooked", "Crunched", "Sautéed", "Worked"):
            with self.subTest(verb=verb):
                self.assertEqual(claude("⏺ Done.", f"✻ {verb} for 10s · done 2:48", *composer()), ("idle", "result"))

    def test_idle_composer_with_a_suggestion_or_typed_text(self):
        self.assertEqual(claude("  ▝▝   ▝▝   ~/Documents/notch_control", *composer('Try "write a test for <filepath>"')),
                         ("idle", None))
        self.assertEqual(claude("⏺ Done.", *composer("1")), ("idle", None))

    def test_screen_text_with_blank_cells_and_non_breaking_spaces(self):
        self.assertEqual(claude(
            "\x00\x00✻\x00Deciphering… (3s · ↓ 12 tokens)", "\x00\x00 ", RULE, "❯\xa0", RULE, "\x00\x00Sonnet 5.5 · notch_control"),
            ("working", None))

    def test_a_named_session_keeps_its_state(self):
        # Claude Code draws the session name inside the top rule once the session is named (`/rename`, `--name`):
        # "──────── ccid-shared-session-fix ─". Real capture: the spinner was above it and the bubble read idle.
        top = "─" * 40 + " ccid-shared-session-fix ─"
        status = ("Sonnet 5.5 · 87% left · AndroidUtils · git:(964-sessao-compartilhada-ccid) · 5h 1% · 7d 17%",
                  "  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent")
        named = [top, "❯", RULE, *status]
        self.assertEqual(claude("✢ Considering… (2m 32s · ↓ 16.2k tokens · still thinking with xhigh effort)", *named),
                         ("working", None))
        self.assertEqual(claude("✻ Worked for 10s · done 2:48", *named), ("idle", "result"))
        self.assertEqual(claude("⏺ Done.", *named), ("idle", None))
        self.assertEqual(claude("Do you want to proceed?", "❯ 1. Yes", "  2. No", *named), ("idle", None))

    def test_waiting_for_background_agents_is_working(self):
        # Real capture: the turn is over but the session is busy until its background agents finish. The line has
        # no "…", and the expanded agent list is drawn below the composer.
        top = "─" * 40 + " ccid-shared-session-fix ─"
        agents = ("  ⏺ main", "  ◯ general-purpose  Editing LoginCcid.kt shareSession       3m 23s · ↓ 64.9k tokens",
                  "  ◯ general-purpose  Waiting on debug APK build               3m 23s · ↓ 61.4k tokens")
        status = ("Sonnet 5.5 · 82% left · AndroidUtils · 5h 9% · 7d 18%", "  ⏵⏵ auto mode on (shift+tab to cycle) · ← 1 agent")
        wait = "✻ Waiting for 2 background agents to finish"
        self.assertEqual(claude("  Assim que os agents entregarem os APKs, rodo o \"antes\".", wait,
                                top, "❯ Pode seguir com os testes", RULE, *status, *agents), ("working", None))
        self.assertEqual(claude(wait.replace("agents", "agent").replace("2", "1"), *composer()), ("working", None))
        # Once the agents are done the wait line is replaced; an older one above does not outlast the finished turn.
        self.assertEqual(claude(wait, "⏺ Done.", "✻ Worked for 3s · done 2:48", *composer()), ("idle", "result"))
        self.assertEqual(claude("⏺ Para saber se está Waiting for 2 background agents, veja a lista.", *composer()), ("idle", None))

    def test_a_named_session_still_asks_for_decisions(self):
        top = "─" * 40 + " ccid-shared-session-fix ─"
        self.assertEqual(claude(top, " Do you want to create probe-file.txt?", " ❯ 1. Yes",
                                "   2. Yes, and switch to accept edits for this session (shift+tab)", "   3. No",
                                " Esc to cancel · Tab to amend"), ("waiting", "approval"))

    def test_permission_dialogs_are_approvals(self):
        bash = ["⏺ Creating directory", " Bash command", "╌" * 40, " mkdir /tmp/x", "╌" * 40, " Do you want to proceed?",
                " ❯ 1. Yes", "   2. Yes, and always allow access to /tmp from this project", "   3. No",
                " Esc to cancel · Tab to amend"]
        edit = [RULE, " Create file", " ../probe-file.txt", "╌" * 40, "   1 hi", "╌" * 40, " Do you want to create probe-file.txt?",
                " ❯ 1. Yes", "   2. Yes, and switch to accept edits for this session (shift+tab)", "   3. No",
                " Esc to cancel · Tab to amend"]
        self.assertEqual(claude(*bash), ("waiting", "approval"))
        self.assertEqual(claude(*edit), ("waiting", "approval"))

    def test_plan_approval_is_waiting(self):
        plan = [RULE, "  Ready to code?", "  Here is Claude's plan:", "╌" * 40, "  Plan: add a file", "╌" * 40, RULE,
                "  Claude has written up a plan and is ready to execute. Would you like to proceed?",
                "  ❯ 1. Yes, auto-accept edits", "    2. Yes, manually approve edits", "    3. Tell Claude what to change",
                "       shift+tab to approve with this feedback", "  ctrl+g to edit in VS Code · ~/.claude/plans/p.md"]
        self.assertEqual(claude(*plan), ("waiting", "approval"))

    def test_ask_user_question_is_a_pending_question(self):
        ask = [RULE, " ☐ Color preference", "Which color do you prefer?", "❯ 1. Red", "     A warm, vibrant color",
               "  2. Blue", "     A cool, calming color", "  3. Type something.", RULE, "  4. Chat about this",
               "Enter to select · ↑/↓ to navigate · Esc to cancel"]
        self.assertEqual(claude(*ask), ("waiting", "question"))

    def test_a_dialog_quoted_above_the_composer_is_not_a_decision(self):
        quoted = ["Here is how the dialog looks:", "Do you want to proceed?", "❯ 1. Yes", "  2. No", *composer()]
        self.assertEqual(claude(*quoted), ("idle", None))
        self.assertEqual(claude(*composer("1. fix this")[:1], "❯ 1. fix this", "  2. then that", RULE, "  status"), ("idle", None))

    def test_a_menu_that_is_not_a_decision_is_left_unclassified(self):
        menu = ["Select model", "❯ 1. Default (recommended) ✔", "  2. Sonnet", "  3. Haiku", "Enter to confirm · Esc to exit"]
        self.assertIsNone(claude(*menu))
        self.assertIsNone(claude("just a shell", "$"))

    def test_older_dialog_wording_still_waits(self):
        older = ["Do you want to proceed?", "❯ 1. Yes", "  2. Yes, and don't ask again for this command",
                 "  3. No, and tell Claude what to do differently (esc)"]
        self.assertEqual(claude(*older), ("waiting", "approval"))

    def test_other_providers_keep_the_tail_rules(self):
        self.assertEqual(classify("Worked for 2s\n› Ask Codex to do anything", "codex"), ("idle", "result"))
        self.assertEqual(classify("• Working (1s • esc to interrupt)\n› Ask Codex to do anything", "codex"), ("working", None))

    def test_turn_from_start_to_the_unseen_result(self):
        found = claude("· Hashing… (1s · thinking)", *composer())
        shown = present(found, None, focused=False)
        self.assertEqual(shown, ("working", None))
        done = claude("✻ Crunched for 2s · done 2:50", *composer())
        self.assertEqual(present(done, shown, focused=False), ("idle", "result"))
        self.assertEqual(present(done, shown, focused=True), ("idle", None))


TOP, BOTTOM = "▄" * 60, "▀" * 60
STATUS = "  notch_control | Codex 5.3 Low Fast | cursor 31.8% | others 75.6% (resets 0m)"


def cursor_composer(text="Add a follow-up", stop=False, footer=(STATUS,)):
    return [TOP, "  → " + text + (" " * 60 + "ctrl+c to stop" if stop else ""), BOTTOM, *footer]


def cursor(*lines):
    return classify(screen(*lines), "cursor")


class CursorAgentScreenTests(unittest.TestCase):
    """Screens captured from Cursor Agent 2026.10.01 in iTerm2, reduced to the interface lines."""

    def test_spinner_and_stop_hint_mean_working(self):
        self.assertEqual(cursor("  Reply with just the word ok.", "⠠⠜ Working", "  Tip: Use /skills to give Cursor knowledge",
                                *cursor_composer(stop=True)), ("working", None))
        self.assertEqual(cursor("  $ curl https://example.com 200ms", "    200", "⠘⠆ Running  26 tokens", "  Tip: Use /skills",
                                *cursor_composer(stop=True, footer=("  1 task", STATUS))), ("working", None))

    def test_spinner_alone_is_working_while_the_user_types_a_follow_up(self):
        self.assertEqual(cursor("⠠⠜ Working", *cursor_composer("what about the tests")), ("working", None))

    def test_an_idle_composer_is_idle_even_with_text_or_a_task_footer(self):
        self.assertEqual(cursor("  ok", *cursor_composer()), ("idle", None))
        self.assertEqual(cursor("  Cursor Agent", *cursor_composer("Plan, search, build anything")), ("idle", None))
        self.assertEqual(cursor("  ok", *cursor_composer("O clique agora está funcionando", footer=("  1 task", STATUS))),
                         ("idle", None))
        self.assertEqual(cursor(*cursor_composer("Plan, search, build anything", footer=("  Plan (shift+tab to cycle)", STATUS))),
                         ("idle", None))

    def test_a_turn_without_a_done_marker_is_a_result_through_the_transition(self):
        shown = present(cursor("⠠⠜ Working", *cursor_composer(stop=True)), None, focused=False)
        self.assertEqual(shown, ("working", None))
        done = cursor("  ok", *cursor_composer())
        self.assertEqual(present(done, shown, focused=False), ("idle", "result"))
        self.assertEqual(present(done, shown, focused=True), ("idle", None))

    def test_question_box_is_a_pending_question(self):
        box = ["┌" + "─" * 60 + "┐", "│ Color Preference                  │", "│ Question 1 of 1                   │",
               "│ 1. Which color do you prefer?     │", "│   › [ ] Red                       │", "│     [ ] Blue                      │",
               "│ ↑/↓ option · ←/→ question · Space select · Enter next/submit · Esc to skip │", "└" + "─" * 60 + "┘"]
        self.assertEqual(cursor("  Use your question tool.", *box), ("waiting", "question"))

    def test_plan_ready_to_build_is_waiting(self):
        box = ["┌" + "─" * 60 + "┐", "│ Plan (failed)                     │", "│ 1. Confirm the target             │",
               "│  Saved to Users/arthu/.cursor/plans/p.plan.md │", "│ Ready to build?                   │",
               "│  → 1. Yes, build locally (b)      │", "│    2. No, propose changes (p or Esc)           │", "└" + "─" * 60 + "┘"]
        self.assertEqual(cursor(*box), ("waiting", "approval"))
        self.assertIsNone(cursor(*box[:4], box[-1]))

    def test_command_approval_options_from_the_agent_source(self):
        # Not captured live: this machine's Cursor config runs every command, so the options come from the agent's code.
        shell = ["  $ rm -rf build  Waiting for approval...", "  → Run (once) (y)", "    Add Shell(rm) to allowlist? (tab)",
                 "    Skip & tell the agent what to do instead (esc or n)"]
        write = ["  → Proceed (y)", "    Reject & propose changes (esc or n or p)", "    Add Write(src/a.py) to allowlist? (tab)"]
        self.assertEqual(cursor(*shell), ("waiting", "approval"))
        self.assertEqual(cursor(*write), ("waiting", "approval"))

    def test_waiting_for_approval_on_the_tool_line_wins_over_the_working_composer(self):
        self.assertEqual(cursor("  $ npm publish  Waiting for approval...", "⠠⠜ Working", *cursor_composer(stop=True)),
                         ("waiting", "approval"))

    def test_options_quoted_above_an_idle_composer_are_not_a_decision(self):
        quoted = ["  The prompt shows:", "  Run (once) (y)", "  Skip (esc or n)", *cursor_composer()]
        self.assertEqual(cursor(*quoted), ("idle", None))

    def test_a_spinner_lookalike_in_old_output_does_not_mean_working(self):
        self.assertEqual(cursor("⠋ Installing dependencies", "  line", "  line", "  line", "  line", *cursor_composer()),
                         ("idle", None))

    def test_screen_without_the_box_falls_back_to_the_tail_rules(self):
        self.assertEqual(cursor("→ Add a follow-up", "Running  2.88k tokens", "ctrl+c to stop"), ("working", None))
        self.assertIsNone(cursor("just a shell", "$"))


if __name__ == "__main__":
    unittest.main()


class CodexScreenTests(unittest.TestCase):
    def test_approval_options_are_not_the_composer(self):
        self.assertEqual(classify(screen('Would you like to run the following command?',
            '› 1. Yes, proceed', "2. Yes, and don't ask again", '3. No, and tell Codex what to do differently'),
            'codex'), ('waiting', 'approval'))

    def test_running_indicator_above_extended_footer_keeps_turn_working(self):
        self.assertEqual(classify(screen(
            '• Reviewing approval request (4m 52s • esc to interrupt)',
            '  1 background terminal running · /ps to view',
            RULE,
            '› Ask Codex to do anything',
            'GPT-6 · Context 14% used · 5h 67% left · weekly 68% left',
            '  /fast to turn on Fast mode'), 'codex'), ('working', None))

    def test_multiline_draft_does_not_hide_running_indicator(self):
        self.assertEqual(classify(screen(
            '• Working (12s • esc to interrupt)', RULE,
            '› follow-up draft', *(['  more draft text'] * 8), RULE,
            'GPT-6 · 5h 67% left'), 'codex'), ('working', None))

    def test_many_background_jobs_do_not_hide_the_activity_indicator(self):
        self.assertEqual(classify(screen('• Working (12s • esc to interrupt)',
            *(['  background terminal job'] * 20), '› Ask Codex to do anything', 'GPT-6'), 'codex'), ('working', None))

    def test_finished_turn_ignores_older_running_marker(self):
        self.assertEqual(classify(screen(
            '• Working (12s • esc to interrupt)', 'tool output',
            '─ Worked for 14s ─────────', 'Finished response', RULE,
            '› Ask Codex to do anything', 'GPT-6 · 5h 67% left'), 'codex'), ('idle', 'result'))

    def test_idle_composer_and_unknown_screen(self):
        self.assertEqual(classify('› Ask Codex to do anything\nGPT-6', 'codex'), ('idle', None))
        self.assertIsNone(classify('streaming output without the composer', 'codex'))
        self.assertIsNone(classify(screen('› previous prompt', *(['streaming output'] * 20)), 'codex'))
