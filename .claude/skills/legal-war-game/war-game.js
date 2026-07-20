export const meta = {
  name: 'legal-war-game',
  description: 'Open-ended courtroom war-game for a legal/terms page: claimant (blind to your clauses) vs you (holding the clauses), judge loops each issue until resolved, then verdict + loophole review.',
  phases: [
    { title: 'Pleadings', detail: 'claim -> defense (written)' },
    { title: 'Hearing', detail: 'judge frames issues; loop each issue until judge rules it resolved; then verdict' },
    { title: 'Review', detail: 'loophole report per scenario' },
  ],
}

// ============ INPUT via args (see SKILL.md) ============
// args = {
//   owner:    string,   // 你方身份画像(只给你方/法官/复盘官,不给对方)
//   legal:    string,   // 你的法律/条款全文摘要(同上,保密)
//   scenarios: [{ key, title, claimantBrief, claimantGoal, respondentGoal }],
//   law:      string,   // optional, 法律体系, default 中华人民共和国法律
//   issueCount: number, // optional, default 3
//   hardCapPerIssue: number // optional, default 40 (仅防脚本失控)
// }
// args may arrive as an object, a JSON string, or (for some loaders) not at all.
let A = args
if (typeof A === 'string') { try { A = JSON.parse(A) } catch (e) { A = undefined } }
const owner = A && A.owner
const legal = A && A.legal
const scenarios = A && A.scenarios
const law = (A && A.law) || '中华人民共和国法律'
const ISSUE_COUNT = (A && A.issueCount) || 3
const HARD_CAP_PER_ISSUE = (A && A.hardCapPerIssue) || 40

if (!owner || !legal || !Array.isArray(scenarios) || scenarios.length === 0) {
  throw new Error('legal-war-game: missing args. typeof args=' + typeof args + ', isArray=' + Array.isArray(args) + ', preview=' + String(args && args.slice ? args.slice(0, 120) : JSON.stringify(args)).slice(0, 200))
}

phase('Pleadings')
log(`法律战沙盘: ${scenarios.length} 个场景, 开放庭审(法官不封顶连追)`)

const results = await pipeline(
  scenarios,
  async (s) => {
    // 起诉:对方只拿 claimantBrief,不给 legal、不给 owner
    const claim = await agent(
      `你是一名资深诉讼律师.\n\n${s.claimantBrief}\n\n目标: ${s.claimantGoal}\n\n请起草《起诉状》:陈述你方掌握的事实、列明诉讼请求、援引法律依据.你不知道对方网站/文件的具体条款,也不知对方详细身份——基于你作为该方律师合理掌握的信息来写.专业犀利.650字内.`,
      { label: `claim:${s.key}`, phase: 'Pleadings' }
    )
    if (!claim) return null

    // 答辩:你方手持条款 + 身份
    const defense = await agent(
      `你是一名资深诉讼律师,代理被告.\n\n${owner}\n你方文件/条款(对方不知内容):\n${legal}\n\n原告《起诉状》:\n${claim}\n\n目标: ${s.respondentGoal}\n\n请起草《答辩状》:逐条反驳,有选择地援引你方条款作防御,指出原告论证与举证漏洞.650字内.`,
      { label: `defense:${s.key}`, phase: 'Pleadings' }
    )
    if (!defense) return null

    phase('Hearing')
    const issues = await agent(
      `你是本案主审法官,依${law}审理本案,现在开庭.被告身份: ${owner}\n\n【起诉状】\n${claim}\n\n【答辩状】\n${defense}\n\n请归纳本案**恰好${ISSUE_COUNT}个**争议焦点,每个焦点一句话点明核心对抗点.真实庭审主持口吻.300字内.`,
      { label: `issues:${s.key}`, phase: 'Hearing' }
    )
    if (!issues) return null

    const transcript = []
    for (let issueIdx = 1; issueIdx <= ISSUE_COUNT; issueIdx++) {
      let resolved = false
      let lastP = ''
      let lastD = ''
      for (let ex = 1; ex <= HARD_CAP_PER_ISSUE && !resolved; ex++) {
        const pArg = await agent(
          `你是原告方代理律师,庭审辩论中.立场: ${s.claimantBrief}\n目标: ${s.claimantGoal}\n\n争议焦点:\n${issues}\n\n${transcript.length ? `庭审至今记录:\n${transcript.join('\n\n')}\n\n` : ''}${lastD ? `被告刚才就本焦点发言:\n${lastD}\n\n` : ''}请就**第${issueIdx}个焦点**发言:紧扣焦点,回应对方与法官的质疑,补强己方.口语化、临场、犀利.260字内.`,
          { label: `i${issueIdx}e${ex}-p:${s.key}`, phase: 'Hearing' }
        )
        if (!pArg) break
        lastP = pArg
        transcript.push(`【焦点${issueIdx}·原告(轮${ex})】\n${pArg}`)

        const dArg = await agent(
          `你是被告方代理律师,庭审辩论中. ${owner}\n你方文件/条款: ${legal}\n\n争议焦点:\n${issues}\n\n${transcript.length ? `庭审至今记录:\n${transcript.join('\n\n')}\n\n` : ''}原告刚才就本焦点发言:\n${pArg}\n\n请就**第${issueIdx}个焦点**发言:紧扣焦点,直接回应原告,用你方条款与事实防御.口语化、临场、冷静专业.260字内.`,
          { label: `i${issueIdx}e${ex}-d:${s.key}`, phase: 'Hearing' }
        )
        if (!dArg) break
        lastD = dArg
        transcript.push(`【焦点${issueIdx}·被告(轮${ex})】\n${dArg}`)

        // 法官裁决:继续追 / 查明 / 制止重复 —— 三选一,循环只看"查明"
        const bench = await agent(
          `你是本案主审法官,依${law}主持庭审.被告身份: ${owner}\n\n争议焦点:\n${issues}\n\n双方就第${issueIdx}个焦点至今的交锋(最近两轮):\n【原告最新】${lastP}\n【被告最新】${lastD}\n\n请裁决本焦点进展,**必须从以下三种中明确择一**:\n(1) 若仍有事实/法律疑点未查清 → 写出"继续追问",并指明问哪一方、具体问什么;\n(2) 若该焦点事实已查清、法律适用已明 → 写出"本焦点查明",并给出你对该焦点的认定结论;\n(3) 若双方开始重复已述观点、无新内容(死缠烂打) → 写出"本焦点查明",并注明"辩论重复,本庭制止,结合全案综合认定".\n真实法官口吻,果断,不纵容无休止重复.260字内.`,
          { label: `i${issueIdx}e${ex}-bench:${s.key}`, phase: 'Hearing' }
        )
        if (!bench) break
        transcript.push(`【焦点${issueIdx}·法官(轮${ex})】\n${bench}`)
        if (bench.includes('本焦点查明')) resolved = true
      }
      if (!resolved) transcript.push(`【焦点${issueIdx}·法官】已达法庭辩论充分程度,本焦点查明,本庭将结合全案证据综合认定.`)
    }

    phase('Review')
    const fullHearing = `【争议焦点】\n${issues}\n\n【庭审辩论全程】\n${transcript.join('\n\n')}`
    const award = await agent(
      `你是本案主审法官,依${law}经书面审理与逐焦点开放庭审辩论(每个焦点均已查明或充分辩论),现在宣判.被告身份: ${owner}\n你方文件/条款:\n${legal}\n\n【起诉状】\n${claim}\n\n【答辩状】\n${defense}\n\n${fullHearing}\n\n请出具《判决书》:归纳争议焦点,结合庭审双方口头交锋的实际表现(谁答得上、谁回避),对条款逐一认定效力,最后作出裁判.中立、依法说理.1000字内.`,
      { label: `award:${s.key}`, phase: 'Review' }
    )
    if (!award) return null

    const review = await agent(
      `你是专精相关法律的资深律师,为你方(被告)复盘一轮开放庭审.\n\n你方文件/条款:\n${legal}\n\n场景: ${s.title}\n\n【庭审焦点+辩论全程】\n${fullHearing}\n\n【判决书】\n${typeof award === 'string' ? award : JSON.stringify(award)}\n\n请输出复盘报告(中文),聚焦:\n1. 在法官反复追问、焦点逐个查清的开放口头对抗下,你方哪些条款经得起盘问、真正防住了?哪些被当庭击穿、绕开或逼出软肋?\n2. 庭审暴露出在你方实际定位下还有什么会让你方实际吃亏的漏洞?区分"能改条款修的"和"条款管不了、只能靠运营/证据的".\n3. 只针对"能改条款修且值得修"的给落地文字建议.不要为你方不会进入的局面过度设防,不要新增进攻性条款.\n4. 按高危/中危/低危分级.\n具体、克制.1200字内.`,
      { label: `review:${s.key}`, phase: 'Review' }
    )
    return { key: s.key, title: s.title, caseFile: { claim, defense, hearing: fullHearing, award }, review }
  }
)

const done = results.filter(Boolean)
log(`庭审完成 ${done.length}/${scenarios.length} 组复盘`)
return done
