(function(global){
  const profiles = {
    dataCenterIT: {
      id:'data-center-it',
      name:'Data Center IT / Infrastructure Operations',
      matches:['data center it','it operations','infrastructure operations','systems administrator','system administrator','infrastructure support','it specialist','operations specialist','server administrator','data center technician it','technical operations'],
      questions:[
        {kind:'Experience',competency:'Troubleshooting',prompt:'Tell me about a difficult infrastructure or systems issue you diagnosed when the symptoms were unclear. Walk me through how you isolated the problem and verified the fix.',probes:['What did you rule out first, and why?','What evidence confirmed the root cause?']},
        {kind:'Scenario',competency:'Incident response',prompt:'Scenario: A customer reports intermittent application timeouts from racks in one data hall. Monitoring looks mostly normal and there are no obvious switch or server alarms. You are the first IT responder. What do you do?',probes:['How would you narrow whether the issue is server, network, cabling, or upstream?','At what point would you escalate, and to whom?']},
        {kind:'Scenario',competency:'Change control',prompt:'Scenario: You are scheduled to patch a critical management server during a maintenance window. Ten minutes before the change, you discover one dependent system is not in the state described in the procedure. What do you do?',probes:['What would make you stop or postpone the change?','What would your rollback and validation plan include?']},
        {kind:'Judgment',competency:'Security & access',prompt:'During a production incident, someone asks you for elevated access they do not normally have because it may speed up troubleshooting. How would you handle the request?',probes:['How would you balance urgency with access control?','What documentation would you expect afterward?']},
        {kind:'Scenario',competency:'Prioritization',prompt:'Scenario: You have a client-impacting ticket, a failed backup alert, and an executive request all arrive within a few minutes. How would you prioritize and communicate your response?',probes:['What factors determine severity for you?','How would you keep lower-priority work from being forgotten?']},
        {kind:'Experience',competency:'Customer communication',prompt:'Tell me about a technical incident where you had to communicate with a customer or non-technical stakeholder while the root cause was still unknown.',probes:['How did you avoid overpromising?','What information did you communicate first?']},
        {kind:'Experience',competency:'Operational improvement',prompt:'Describe a recurring IT problem you eliminated or made easier to diagnose through automation, monitoring, documentation, or a process change.',probes:['How did you measure whether the improvement worked?','How did you make the improvement repeatable for the rest of the team?']}
      ]
    },
    criticalFacilities: {
      id:'critical-facilities',
      name:'Critical Facilities / Data Center Operations',
      matches:['critical facilities','critical facility','facilities technician','facilities engineer','data center operations','data centre operations','critical operations','mechanical technician','electrical technician','building engineer','facility engineer','facility technician'],
      questions:[
        {kind:'Experience',competency:'Safety & procedure',prompt:'Tell me about a time you stopped or changed work because field conditions no longer matched the approved procedure or your safety expectations.',probes:['What specifically caused you to stop?','How did you communicate the stop-work decision?']},
        {kind:'Scenario',competency:'Incident response',prompt:'Scenario: A utility power event causes several cooling units to stop at the same time, but temperatures are still within limits. What are your first actions?',probes:['What information would you gather before touching equipment?','How would you balance restoration speed with avoiding a second failure?']},
        {kind:'Scenario',competency:'Electrical resilience',prompt:'Scenario: A PDU input breaker trips and several racks are left on a single remaining power path. The load is stable and there is no immediate client outage. How would you respond?',probes:['What would you verify before any transfer or breaker operation?','What conditions would require immediate escalation?']},
        {kind:'Scenario',competency:'Mechanical systems',prompt:'Scenario: During planned cooling maintenance, you notice a valve position does not match the approved MOP and the system is still carrying load. What do you do next?',probes:['What would you validate before changing the valve position?','How would you protect redundancy while troubleshooting?']},
        {kind:'Judgment',competency:'Change management',prompt:'A vendor says a minor deviation from the approved procedure will save twenty minutes and is low risk. How would you handle that situation?',probes:['What would you require before allowing any deviation?','Who needs to be involved in the decision?']},
        {kind:'Experience',competency:'Communication',prompt:'Describe a high-pressure facilities incident where you had to keep operations leadership, customers, or another team informed while troubleshooting was still underway.',probes:['How did you separate confirmed facts from assumptions?','How did you decide the update cadence?']},
        {kind:'Experience',competency:'Handoff & learning',prompt:'Tell me about an incident or maintenance activity where a strong shift handoff, post-event review, or procedure update prevented future risk.',probes:['What changed in the procedure afterward?','How did you verify the learning was adopted?']}
      ]
    },
    network: {
      id:'network',
      name:'Network / Telecom Operations',
      matches:['network engineer','network operations','network analyst','noc','telecom','telecommunications','network administrator','network technician','network architect','carrier services'],
      questions:[
        {kind:'Experience',competency:'Network troubleshooting',prompt:'Tell me about a difficult network issue you diagnosed when monitoring and user symptoms did not clearly agree.',probes:['What did you test first?','How did you prove where the fault domain was?']},
        {kind:'Scenario',competency:'Layered troubleshooting',prompt:'Scenario: Users in one area report intermittent packet loss, but interface counters and monitoring show no obvious errors. How would you troubleshoot the issue from the endpoint toward the upstream network?',probes:['What data would you capture during the failure?','How would you test whether the problem is physical, switching, routing, or application-related?']},
        {kind:'Scenario',competency:'Redundancy',prompt:'Scenario: One redundant network path is down for maintenance and the remaining path begins showing elevated latency. There is no outage yet. What would you do?',probes:['What thresholds would trigger rollback or escalation?','How would you reduce risk while maintaining service?']},
        {kind:'Scenario',competency:'Change control',prompt:'Scenario: You are preparing a routing or switching change and discover that the live configuration differs from the documented baseline. How do you proceed?',probes:['What do you validate before making the change?','What would your rollback criteria be?']},
        {kind:'Judgment',competency:'Security',prompt:'A troubleshooting request asks you to temporarily bypass a network security control to isolate an issue. How would you evaluate and handle the request?',probes:['What safer alternatives would you consider first?','What authorization and logging would you require?']},
        {kind:'Experience',competency:'Carrier & vendor management',prompt:'Tell me about a carrier or vendor issue where the provider initially said their service was healthy but you believed the fault was upstream.',probes:['What evidence did you present?','How did you keep the escalation productive?']},
        {kind:'Experience',competency:'Documentation',prompt:'Describe a network documentation, monitoring, or automation improvement you implemented that made outages easier to diagnose or changes safer.',probes:['What problem did the improvement solve?','How did other engineers use it afterward?']}
      ]
    },
    serviceDesk: {
      id:'service-desk',
      name:'Service Desk / Desktop Support',
      matches:['service desk','help desk','helpdesk','desktop support','end user support','technical support','it support','support analyst','support technician','field support'],
      questions:[
        {kind:'Experience',competency:'Customer service',prompt:'Tell me about a frustrated user you helped with a technical problem. How did you keep the interaction productive while still solving the issue?',probes:['What did you say when the user was frustrated?','How did you confirm the issue was fully resolved?']},
        {kind:'Scenario',competency:'Troubleshooting',prompt:'Scenario: A user says no websites load in any browser, but messaging and some cloud applications still work. What would you check and in what order?',probes:['How would you distinguish a device problem from DNS, proxy, VPN, or network issues?','What would make you escalate the ticket?']},
        {kind:'Scenario',competency:'Security awareness',prompt:'Scenario: A user calls saying they clicked a suspicious link and entered their password. They are embarrassed and ask you not to report it. What do you do?',probes:['What immediate containment steps would you take?','How would you communicate with the user without discouraging future reporting?']},
        {kind:'Scenario',competency:'Prioritization',prompt:'Scenario: An executive has a meeting starting in ten minutes and cannot present, while multiple employees are also reporting a new login issue. How would you prioritize the work?',probes:['How would you determine whether the login issue is a broader incident?','How would you communicate wait times to both groups?']},
        {kind:'Experience',competency:'Escalation',prompt:'Tell me about a ticket you could not resolve yourself. How did you decide when to escalate and what information did you provide to the next team?',probes:['What troubleshooting did you complete before escalating?','How did you prevent the user from having to repeat everything?']},
        {kind:'Scenario',competency:'Device lifecycle',prompt:'Scenario: A newly provisioned laptop is enrolled in management but required corporate applications and policies are not appearing. How would you troubleshoot the onboarding path?',probes:['What systems or logs would you check?','How would you determine whether the issue is device-specific or service-wide?']},
        {kind:'Experience',competency:'Knowledge management',prompt:'Describe a support issue that led you to create or improve a knowledge article, script, or standard troubleshooting process.',probes:['How did you make the content useful to someone less experienced?','Did it reduce repeat tickets or resolution time?']}
      ]
    },
    cybersecurity: {
      id:'cybersecurity',
      name:'Cybersecurity / Security Operations',
      matches:['cybersecurity','cyber security','security analyst','soc analyst','security engineer','information security','infosec','incident response analyst','security operations'],
      questions:[
        {kind:'Scenario',competency:'Detection & triage',prompt:'Scenario: You see a successful login to a privileged account from an unusual location followed by access to several systems. What are your first steps?',probes:['What evidence would you preserve first?','How would you decide whether to disable the account immediately?']},
        {kind:'Experience',competency:'Incident response',prompt:'Tell me about a security event you investigated where the initial alert did not tell the full story.',probes:['How did you establish scope?','What evidence changed your original hypothesis?']},
        {kind:'Scenario',competency:'Endpoint security',prompt:'Scenario: An endpoint tool reports suspicious PowerShell activity on a workstation belonging to a critical user. The user says they are in the middle of urgent work. What do you do?',probes:['How would you balance containment and business impact?','What would determine whether the device should be isolated?']},
        {kind:'Scenario',competency:'Vulnerability management',prompt:'Scenario: A critical vulnerability is announced for software used across the company, but there is no patch yet. How would you reduce risk while waiting for a fix?',probes:['How would you prioritize affected systems?','What compensating controls would you consider?']},
        {kind:'Judgment',competency:'Privileged access',prompt:'A senior leader asks for a standing administrative permission because repeated approvals are slowing down their work. How would you respond?',probes:['What principle would guide your decision?','What alternatives could meet the business need with less risk?']},
        {kind:'Scenario',competency:'Phishing response',prompt:'Scenario: Several employees report similar phishing messages and one person confirms they submitted credentials. How would you manage the incident from containment through recovery?',probes:['What actions would you take beyond the single user?','What indicators would you search for across the environment?']},
        {kind:'Experience',competency:'Security communication',prompt:'Describe a time you had to explain a meaningful security risk to a non-security audience and get them to take action.',probes:['How did you translate technical risk into business impact?','How did you handle pushback?']}
      ]
    },
    projectProgram: {
      id:'project-program',
      name:'Project / Program Management',
      matches:['project manager','program manager','project coordinator','program coordinator','pmo','implementation manager','delivery manager','technical program manager'],
      questions:[
        {kind:'Experience',competency:'Planning',prompt:'Tell me about a complex project with several dependencies. How did you build the plan and make sure the critical path was understood?',probes:['How did you surface hidden dependencies?','How did you keep the plan current?']},
        {kind:'Scenario',competency:'Risk management',prompt:'Scenario: A key vendor says a critical deliverable will be three weeks late and the launch date is fixed. What do you do in the first twenty-four hours?',probes:['How would you evaluate alternatives?','How would you communicate the impact without creating unnecessary alarm?']},
        {kind:'Scenario',competency:'Scope control',prompt:'Scenario: An executive requests a significant feature late in the project and describes it as a small change. How would you respond?',probes:['How would you quantify the impact?','How would you preserve the relationship while protecting the project?']},
        {kind:'Experience',competency:'Stakeholder management',prompt:'Describe a project where two important stakeholders wanted different outcomes. How did you create alignment?',probes:['What tradeoffs did you make visible?','Who ultimately made the decision?']},
        {kind:'Scenario',competency:'Execution',prompt:'Scenario: Two workstreams both claim the other team owns a blocking task, and the milestone is approaching. How would you resolve the ownership gap?',probes:['How would you prevent the issue from repeating?','What would you escalate and when?']},
        {kind:'Experience',competency:'Executive communication',prompt:'Tell me about a time you had to give leadership bad news about schedule, cost, or risk.',probes:['What did you include in the update?','What options did you bring with the problem?']},
        {kind:'Experience',competency:'Continuous improvement',prompt:'Describe a project that did not go as planned. What did you change in your project-management approach afterward?',probes:['What was the root cause?','How did you know the new approach worked better?']}
      ]
    },
    peopleLeadership: {
      id:'people-leadership',
      name:'People Leadership / Operations Management',
      matches:['manager','supervisor','director','team lead','people leader','operations manager','it manager','facilities manager','service desk manager','network manager'],
      questions:[
        {kind:'Experience',competency:'Coaching',prompt:'Tell me about an employee whose performance was inconsistent. How did you diagnose the problem and coach them toward better results?',probes:['How did you set measurable expectations?','What changed as a result of your coaching?']},
        {kind:'Scenario',competency:'Operational leadership',prompt:'Scenario: Two serious incidents occur at the same time and both teams believe their issue deserves your immediate attention. How would you lead through the situation?',probes:['How would you delegate?','What information would you require before changing priorities?']},
        {kind:'Scenario',competency:'Accountability',prompt:'Scenario: A strong performer repeatedly ignores a documented process because they believe their way is faster. Their results are usually good. How would you handle it?',probes:['How would you distinguish innovation from unacceptable risk?','What would you do if the behavior continued?']},
        {kind:'Experience',competency:'Difficult conversations',prompt:'Describe a difficult performance or behavior conversation you had with an employee. How did you prepare and what happened afterward?',probes:['How did you keep the conversation fair and specific?','What follow-up did you put in place?']},
        {kind:'Scenario',competency:'Staffing & coverage',prompt:'Scenario: You have an after-hours support gap next week and every qualified team member already has a legitimate conflict. How would you solve the coverage problem?',probes:['How would you balance fairness and operational responsibility?','What longer-term change might prevent the same problem?']},
        {kind:'Experience',competency:'Prioritization',prompt:'Tell me about a period when your team had more work than capacity. How did you decide what would not get done?',probes:['How did you communicate the tradeoffs upward and downward?','What data informed your decision?']},
        {kind:'Experience',competency:'Culture & standards',prompt:'Describe something you changed that improved team standards, ownership, communication, or operational discipline.',probes:['How did you gain adoption?','How did you know the culture actually changed?']}
      ]
    },
    customerBusiness: {
      id:'customer-business',
      name:'Customer Success / Account / Sales Operations',
      matches:['customer success','account manager','account executive','sales','client services','client success','customer experience','business development','service delivery'],
      questions:[
        {kind:'Experience',competency:'Customer ownership',prompt:'Tell me about a difficult customer situation where the problem was not entirely within your control but you still owned the outcome.',probes:['How did you rebuild confidence?','What did you commit to, and what did you avoid promising?']},
        {kind:'Scenario',competency:'Escalation management',prompt:'Scenario: A major customer is impacted by an outage and asks for an immediate root cause while the technical teams are still investigating. How would you respond?',probes:['What would you communicate before the root cause is known?','How would you coordinate with the technical incident team?']},
        {kind:'Scenario',competency:'Expectation management',prompt:'Scenario: A customer expects a feature or service level that was never included in the agreement, but they believe it was promised during the sales process. What do you do?',probes:['How would you verify what was actually committed?','How would you preserve the relationship while correcting expectations?']},
        {kind:'Experience',competency:'Retention',prompt:'Describe a customer relationship that was at risk. What signals did you see and what actions did you take?',probes:['What was the underlying cause of the risk?','How did you measure whether the relationship improved?']},
        {kind:'Scenario',competency:'Prioritization',prompt:'Scenario: Three strategic customers all request urgent help at the same time and your team cannot respond to all three immediately. How would you prioritize?',probes:['What criteria would you use?','How would you communicate with the customers who must wait?']},
        {kind:'Experience',competency:'Cross-functional influence',prompt:'Tell me about a customer issue that required another internal team to change priorities or behavior. How did you influence the outcome without direct authority?',probes:['What resistance did you encounter?','How did you keep the customer informed?']},
        {kind:'Experience',competency:'Business judgment',prompt:'Describe a time you had to say no to a customer request because accepting it would have created unacceptable cost, risk, or precedent.',probes:['How did you explain the decision?','What alternative did you offer?']}
      ]
    },
    general: {
      id:'general',
      name:'General Professional Interview',
      matches:[],
      questions:[
        {kind:'Experience',competency:'Problem solving',prompt:'Tell me about a difficult problem you solved when the answer was not obvious.',probes:['How did you break the problem down?','What did you learn from the result?']},
        {kind:'Scenario',competency:'Judgment',prompt:'Scenario: You discover a problem that could affect a customer or another team, but you are not yet certain of the cause. What would you do?',probes:['What would you communicate before you know the full answer?','When would you escalate?']},
        {kind:'Experience',competency:'Ownership',prompt:'Tell me about a time you took ownership of something that was not clearly assigned to you.',probes:['Why did you decide to step in?','How did you know the issue was resolved?']},
        {kind:'Scenario',competency:'Prioritization',prompt:'Scenario: You receive three urgent requests from different stakeholders and cannot complete all of them at once. How would you decide what to do first?',probes:['What information would you gather?','How would you communicate the tradeoff?']},
        {kind:'Experience',competency:'Communication',prompt:'Describe a time you had to explain a complex issue to someone with less subject-matter knowledge than you.',probes:['How did you adapt your explanation?','How did you confirm understanding?']},
        {kind:'Experience',competency:'Learning agility',prompt:'Tell me about something important you had to learn quickly in order to deliver a result.',probes:['How did you decide what to learn first?','How did you apply the new knowledge?']},
        {kind:'Experience',competency:'Collaboration',prompt:'Describe a situation where you disagreed with a teammate or partner but still needed to deliver a shared result.',probes:['How did you handle the disagreement?','What was the final outcome?']}
      ]
    }
  };

  function normalize(value){return String(value||'').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim()}
  function resolveRole(role){
    const r=normalize(role);
    let best=profiles.general,bestScore=0;
    Object.values(profiles).forEach(profile=>{
      if(profile.id==='general')return;
      let score=0;
      profile.matches.forEach(term=>{
        const t=normalize(term);
        if(r===t)score=Math.max(score,100+t.length);
        else if(r.includes(t))score=Math.max(score,60+t.length);
        else{
          const words=t.split(' ').filter(w=>w.length>3);
          const hits=words.filter(w=>r.includes(w)).length;
          if(hits)score=Math.max(score,hits*10);
        }
      });
      if(score>bestScore){best=profile;bestScore=score}
    });
    return best;
  }
  function spoken(question){
    return question.kind==='Scenario' && !/^scenario:/i.test(question.prompt)
      ? 'I’d like to give you a scenario. '+question.prompt
      : question.prompt;
  }
  global.INTERVIEW_ROLE_LIBRARY={profiles,resolveRole,spoken};
})(window);
