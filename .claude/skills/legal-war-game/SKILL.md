---
name: legal-war-game
description: Red-team a legal/terms/copyright/privacy page by simulating open-ended courtroom litigation. Use when the user wants to stress-test, harden, or find loopholes in 法律声明/条款/版权页 (e.g. "模拟诉讼检验我的声明", "war-game this legal page", "找条款漏洞", "pressure-test my disclaimer against 视觉中国-style claims"). Spawns a blind claimant vs the clause-holder, an active judge who loops each issue until resolved, then a verdict + loophole review.
---

# Legal War-Game (法律战沙盘)

Red-teams a legal/terms page by running **open-ended mock litigation** against it. The goal is to find which clauses actually hold up under adversarial oral argument — and which get torn apart — so you can harden the text.

The deliverable is a per-scenario report: full case file (起诉状 → 答辩状 → 庭审记录 → 判决书) plus a loophole review (复盘).

## The driver is `war-game.js`

`.claude/skills/legal-war-game/war-game.js` is a Workflow script. Run it with the **Workflow** tool, passing the inputs via `args`. You do NOT edit the script to change the scenario — you pass different `args`.

## How to run (the agent path)

Call `Workflow` with `scriptPath` pointing at the script and `args` carrying the four inputs:

```
Workflow({
  scriptPath: ".claude/skills/legal-war-game/war-game.js",
  args: {
    owner:    "<你方身份画像 — 只给你方/法官/复盘官, 不给对方>",
    legal:    "<你的法律/条款全文摘要 — 同上, 保密>",
    scenarios: [
      {
        key: "vcg-infringement",
        title: "视觉中国图片侵权索赔之诉",
        claimantBrief: "<对方律师视角: 他是谁、要什么、手里有什么牌. 不给他看你的条款>",
        claimantGoal:  "尽可能拿到赔偿, 用惯用的批量维权与举证施压打法.",
        respondentGoal: "驳回或最大限度压低索赔. 手持你方条款, 可援引防御."
      }
    ],
    law: "中华人民共和国法律",      // optional, default
    issueCount: 3,                   // optional, default 3 焦点
    hardCapPerIssue: 40              // optional, 仅防脚本失控
  }
})
```

It runs in the background; you get a task-notification with the JSON result when done.

## The four inputs (what to fill)

- **`owner`** — who YOU are (the defendant / clause-holder), with the facts that matter legally (e.g. minor + legal guardians, non-profit, student). Given to your side, the judge, and the reviewer — **never to the claimant**.
- **`legal`** — the full text/summary of your clauses, translated into the bracketed summary form. Same visibility as `owner`. This is the "shield" being tested.
- **`scenarios`** — one entry per adversarial situation. For each:
  - `claimantBrief` — the opposing lawyer's point of view ONLY: who they are, what they want, what evidence they hold. **Do not leak your clauses or identity here** — blind opposition is the whole point (a real plaintiff doesn't get your terms up front).
  - `claimantGoal` / `respondentGoal` — what each side is trying to achieve.
- **`law`** — governing legal system for the judge.

## The process it runs (why it's built this way)

1. **Pleadings (书面诉答)** — claimant drafts 起诉状 blind; you draft 答辩状 holding the clauses.
2. **Hearing (开放庭审)** — judge frames N issues, then **loops each issue**: claimant argues → you defend → judge rules one of {继续追问 / 本焦点查明 / 本焦点查明(制止重复)}. The issue only closes when the judge declares it resolved — no fixed round cap. This is what separates real oral debate from one-shot document ping-pong.
3. **Verdict + Review** — judge rules on each clause's validity and the case; a reviewer then separates "fixable by editing clauses" from "only fixable by ops/evidence", and refuses to over-engineer for situations you won't enter.

## Lessons baked in (from 6 live iterations — don't relearn these)

- **Blind the claimant.** Never put your clauses/identity in `claimantBrief`. Leaking them makes the plaintiff superhuman and the test useless.
- **Let the judge control the loop.** A fixed round count produces repetitive "each side restates" debate. The judge-resolves-it loop is what surfaces real weak points (it once chased ownership for 7–8 rounds into RAW-fingerprint forensics).
- **Read the review for the split that matters**: *clauses* only make you "not lose"; *facts/evidence* make you "win". Most high-risk leftovers are ops problems (source attribution logs, response-time discipline, traffic data), not text.
- **Don't over-engineer.** Reviewer is instructed to skip clauses for situations you won't enter and to reject offensive/aggressive clauses you can't back in court.

## Output handling

The result is an array of `{ key, title, caseFile, review }`. Archive it to `_drafts/legal-war-game-<n>.md` (or wherever the user keeps drafts) and summarize the verdicts + the fixable-vs-ops loophole split. Commit only when the user says to.
