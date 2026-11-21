# Team ledger: purva-main + purva-esg

One shared record of who changed what, in **both** repos. It lives only here, in purva-main. purva-esg changes are logged here too.

People: **Teja** (Teja Chey) and **Smruthi** (SmruthiChandrashekar). Both use Claude Code. The rules for using this file are in `CLAUDE.md` (same rules in both repos).

**In short:**
1. Pull both repos and read this file before starting.
2. Claim your work under **In progress** and push the claim.
3. Do the work.
4. Add a **Log** entry, remove your claim, and push in the same commit as the work.

---

## In progress

Claim work here **before** editing, so the other person doesn't touch the same files. Remove your row when you push the finished work. A claim older than 2 days with no matching log entry can be asked about or cleared.

| Who | Started | Repos | Files / area | What |
|-----|---------|-------|--------------|------|
| _(none)_ | | | | |

---

## Log

Newest first. One entry per finished change (a fix in both repos is one entry).

**Entry format:**
```
### YYYY-MM-DD · Who · short title
- Repos: main <commit> · esg <commit>   (or "main only" / "esg only")
- What: one or two plain sentences on what changed and why.
- Files: the main files touched
- Deploy: what has to be redeployed (Vercel / Render / Supabase SQL), or "none"
- Follow-up: anything left open (optional)
```

### 2026-11-21 · Teja · Rolled back the chatbot safety guardrails
- Repos: main 0a0cc75 · esg 279d0fb
- What: Undid the 2026-11-20 safety guardrails change (main 841d1de, esg e89caa9) because the chat looked broken after it. The chatbot and complaint forms are back to how they were before that change.
- Files: backend/agent/safety.py (removed), backend/agent/graph.py, backend/agent/state.py, backend/agent/nodes/classify_severity.py, backend/agent/nodes/generate_response.py, backend/main.py, frontend Chatbot.jsx, PolicyAssistant.jsx, SafetyBadge (removed)
- Deploy: Azure backend and website redeploy automatically on push
- Follow-up: the guardrails can be brought back later with `git revert 0a0cc75` once the problem is found

### 2026-11-20 · Teja · Chatbot safety guardrails
- Repos: main 841d1de · esg e89caa9
- What: Every chat message and complaint-form text now passes a safety gate before triage (`backend/agent/safety.py`). Rules catch clear cases instantly: crisis wording, first-person harm such as "can i bomb my apartment", and injection phrases. Llama Prompt Guard 2 flags jailbreaks. gpt-oss-20b on Groq follows our written policy for subtle cases (off-topic, abuse, rephrased harm), with gpt-oss-safeguard-20b as backup. The safeguard model only allows 3 requests a minute on the free plan, and Llama Guard 4 is retired on Groq. Reports of harm by others ("my supervisor threatened to kill me") always reach triage as real complaints.
  - Blocked messages get a fixed reply (crisis: 112 and Tele-MANAS 14416), no severity, no form and no signed pass. They're logged ("SAFETY GATE" in the backend log), and the chat shows a "Safety guardrail" badge.
  - Triage now treats only reports by others as HIGH.
  - User text is kept out of the system prompts.
  - Policy answers end with "The official policy document is the final reference."
  - On forms, harmful-intent text is capped at Medium for human review, never dropped.
- Tests: 43 new safety tests. All 180 offline tests pass in main. Live check on a local backend: bomb → refused, threat report → HIGH/HR, crisis → helplines, injection → refused, IPL question → out of scope, POSH question → policy answer.
- Files: backend/agent/safety.py (new), graph.py, state.py, nodes/classify_severity.py, nodes/generate_response.py, main.py, tests/test_safety_gate.py (new), tests/conftest.py, frontend SafetyBadge.jsx/.css (new), Chatbot.jsx, PolicyAssistant.jsx
- Deploy: backend + website (Azure deploys on push). No new settings: it uses the existing GROQ_API_KEY. Optional: SAFETY_MODEL_ENABLED=false turns the AI checks off (rules stay).
- Follow-up: phases 2–3 of CHATBOT_SAFETY_PLAN (answer grounding check, safety-event log table and review screen). The ESG tests test_turn_2_harassment_followup and test_turn_2_snag_followup already failed before this change (single-department mode).

### 2026-11-18 · Teja · Top-bar "Dashboard" link renamed to "Home"
- Repos: main 884c44e · esg not needed (already says Home)
- What: When logged in, the top bar's link to the GRM home page (/grm) was labelled "Dashboard", right above the home page's own "Dashboard" button, so there were two different "Dashboards". The link now says Home (all 3 languages); the dashboard is reached from the home page button, as before.
- Files: frontend/src/components/Navbar.jsx
- Deploy: website (Vercel; Azure deploys on push)

### 2026-11-18 · Teja · Logout no longer pushed off the screen on desktop
- Repos: main 2cc698d · esg 4df92a2
- What: On wide screens the bar showed the full name ("Hi, SMRUTHI CHANDRASHEKAR"), and with the Purva link added the bar no longer fitted its 1320px width, so Logout went off screen (seen on the Azure site). The bar now shows the first name only (full name on hover), the links sit a little closer on desktop, and the name is the one thing that shrinks with "…" if space runs out. Measured user, admin and super admin at 1200–1920px with a short and a 30-letter name: Logout always fits. Phones/tablets unchanged.
- Files: frontend/src/components/Navbar.jsx, frontend/src/styles/responsive.css
- Deploy: website (Vercel; Azure Static Web Apps deploys on push)

### 2026-11-18 · RishabhWDB · Website can move from Vercel to Azure
- Repos: main c4d733e (main only; esg not done)
- What: Added files to host the website on Azure Static Web Apps (Free plan), next to the backend that already runs on Azure. New files only; the frontend code, vercel.json and the Vercel project are unchanged, so the site stays on Vercel until the switch.
- Files: deploy/staticwebapp.config.json, deploy/azure-frontend.sh, deploy/vercel-env.sh, deploy/AZURE-WEBSITE.md, .github/workflows/azure-frontend.yml, deploy/AZURE.md (link)
- Deploy: none yet. Steps in deploy/AZURE-WEBSITE.md: supervisor runs azure-frontend.sh and azure.sh in Cloud Shell; Smruthi sets AZURE_STATIC_WEB_APP and the VITE_* Actions variables and runs `gh workflow run azure-frontend.yml`.
- Follow-up: the website address changes (QR codes point at purva-main.vercel.app). Keep Vercel until they are reprinted, or set up a company domain. At the switch: Supabase Auth URLs and FRONTEND_URL.

### 2026-11-18 · RishabhWDB · Azure: use the shared Container Apps environment
- Repos: main 2064d16 (main only)
- What: The Azure free trial allows only one Container Apps environment and another project already has it, so purva-main now runs in that environment (`purva-bot-env`) instead of its own. Its app, secrets, settings, registry and deploy identity are still separate, and no setting was renamed (settings belong to each app, so they can't clash).
- Files: deploy/azure.sh, deploy/github-setup.sh, deploy/AZURE.md
- Deploy: none yet. In Cloud Shell: `git pull`, then `bash deploy/azure.sh` (without LOCATION) and `bash deploy/github-setup.sh`.
- Follow-up: if the other project ever deletes or recreates `purva-bot-env`, this app goes down with it.

### 2026-11-18 · RishabhWDB · Backend can run on Azure Container Apps
- Repos: main a460761 (main only; esg not done)
- What: Added a Dockerfile and deploy scripts so the backend can run on Azure Container Apps in its own resource group (`purva-main`), with a GitHub Actions deploy on every push to main that changes the backend. New files only (plus `.env.azure` in `.gitignore`); the app code, Render and Vercel are unchanged.
- Files: Dockerfile, .dockerignore, deploy/render-env.sh, deploy/azure.sh, deploy/github-setup.sh, deploy/AZURE.md, .github/workflows/azure.yml, .gitignore
- Deploy: none yet. Steps in deploy/AZURE.md: the supervisor runs the scripts in Azure Cloud Shell, then Smruthi sets 4 GitHub Actions variables and runs `gh workflow run azure.yml`. The workflow does nothing until those variables exist.
- Follow-up: when switching the website to Azure, change `VITE_API_BASE_URL` in Vercel and suspend Render soon after (both backends run the SLA monitor, so escalation emails can go out twice).

### 2026-11-18 · Smruthi · Complaint forms check for enough detail, like the chat
- Repos: main c944aaf · esg c97bf2f
- What: On Submit, every complaint form now runs the same "is there enough detail (what, where, when)?" check as the chat, through the new `/api/agents/check-complaint`. If details are missing, the chatbot popup opens and asks; the answer is added to the form's description under "Additional details" and the person reviews and presses Submit. At most 2 questions; urgent reports (harassment, safety, bribery) are never held up; "Submit without these details" is always offered; if the check fails the form is filed as before. Complaints handed over from the chat skip it (already checked there). ESG only: the chatbot now shows for guests too (no saved history, voice or "Speak to a Human", which need a login), the guest form uses the same follow-ups, and the chatbot's form button sends guests to the guest form (`/login?mode=guest`).
- Files: backend/main.py, backend/tests/test_form_detail_check.py (new), frontend/src/utils/formFollowup.js (new), frontend/src/components/FollowupNotice.jsx (new), Chatbot.jsx, LodgeExternal/LodgeInternal/LodgeContract.jsx; esg also GuestComplaintForm.jsx, Layout.jsx, Auth.jsx
- Deploy: Render (both backends) and Vercel (both)
- Follow-up: the popup flow was not tried in a browser before pushing; worth a quick check after deploy. Each form submit is one more Groq call.

### 2026-11-18 · Smruthi · Emails show the real portal link, not Brevo's tracking link
- Repos: main 560b6f1 · esg 98ee708
- What: Brevo's click tracking turned every link in our plain-text emails into a long tracking address, so admins saw that instead of the portal link. Every email the app sends now also has an HTML version whose visible link text is the real address (Brevo can still count clicks behind it). Applies to all app emails, including complainant emails.
- Files: agents/escalation/notifier.py
- Deploy: Render (both backends)

### 2026-11-18 · Teja · Safari "Application Error" after a deploy
- Repos: main a4b11bf · esg 544032e
- What: Every deploy renames and deletes the old page code files. In a tab opened before the deploy, Vercel answered requests for the old files with the HTML page. Safari then showed "'text/html' is not a valid JavaScript MIME type", which the reload-once fix didn't recognise (it only knew Chrome and Firefox wording). Now missing /assets/ files return 404, and the Safari wordings also trigger the one automatic reload.
- Files: frontend/vercel.json, frontend/src/utils/newVersionReload.js
- Deploy: Vercel (both)

### 2026-11-18 · Teja · Shared ledger and Claude Code rules
- Repos: main (LEDGER.md + CLAUDE.md, this commit) · esg 7f98d32 (CLAUDE.md)
- What: Started this ledger and added CLAUDE.md rules so both Claude Code setups work the same way.
- Files: LEDGER.md, CLAUDE.md
- Deploy: none

### 2026-11-18 · Smruthi · Admin portal link in complaint emails
- Repos: main a3158ff, ca4de3c · esg 01bf886, 44014c8
- What: The High-severity alert emails sent to staff when a complaint comes in now end with a link to the admin portal (`FRONTEND_URL` + `/admin/login`). There are two such emails: one for chatbot complaints (a3158ff / 01bf886) and one for form complaints (ca4de3c / 44014c8). If `FRONTEND_URL` is empty, the email keeps the old "Please log in" line with no link.
- Files: backend/agent/nodes/department_router.py (chatbot complaints), agents/escalation/escalation_agent.py (form complaints)
- Deploy: Render (both backends), with `FRONTEND_URL` set in each service's Environment

### 2026-11-18 · Teja · "File a complaint" goes straight to the user's own form
- Repos: main 3530c0b · esg not needed (it has one form)
- What: The top-bar button sent logged-in users to "Select Stakeholder Category" again. It now uses the type on their profile (Internal / Contract / External). The category page also forwards people who already have a type.
- Files: frontend/src/utils/lodgeRoute.js (new), Navbar, LodgeSelection, Profile, Dashboard, Chatbot, StakeholderHub
- Deploy: Vercel (purva-main)

### 2026-11-18 · Teja · QR scans never show an old cached version
- Repos: main 88abe4d · esg 8a83e5a
- What: The offline service worker served an old saved index.html, so returning phones saw the old simulation, then "Application Error", then the home page. Page loads are now network-first, with the saved copy used only offline. A newer worker reloads the page once.
- Files: frontend/vite.config.js, frontend/src/main.jsx
- Deploy: Vercel (both)
- Follow-up: phones that cached a very old build may see it once more.

### 2026-11-18 · Teja · Complaint lists become cards on phones and tablets
- Repos: main c7e6a03 · esg 57dc657
- What: Below 1200px, admin, citizen and super-admin lists are cards, with no sideways scrolling. Also fixed the navbar overlap at 1280px for super admin.
- Files: frontend/src/styles/responsive.css, AdminDashboard, Dashboard, SuperAdminPortal
- Deploy: Vercel (both)

### 2026-11-18 · Teja · Trigger redeploy after the repos went private
- Repos: main b243514 · esg 724a46f (empty commits)
- Deploy: Render backends need a Manual Deploy if they are still on old code.

### 2026-11-17 · Teja · Office QR test fixes (details in CHANGES_2026-11-17)
- Repos: main c8d3f12, 73d796f, 8d903b1, 99f8c7a, 1249695, ed7f5a6 · esg d0f2221, 186c09c, f21a50c, 63b7def, bf0a6d8, 1d0346b
- What:
  - The portal is the front door; the simulation is removed.
  - Optional project picker in every form.
  - Guest complaints (ESG, 1 per hour).
  - Low-priority concerns show the policy answer with a "File it anyway" option.
  - Complaint owner is taken from the login.
  - Fixed the open redirect after login.
  - Signed chatbot severity (`ESCALATION_SECRET`).
  - Responsive layout everywhere.
  - Reload once instead of "Application Error".
- Deploy: Vercel + Render (both). Optional env: ESCALATION_SECRET.

### 2026-11-16 · Smruthi · Responsive UI
- Repos: main 67262f6 (merged ca17763) · esg e6b85da (ported by Teja)
- What: Made the UI responsive on phones, tablets and small laptops.

### 2026-11-16 · Teja · Handover, security and reliability
- Repos: main 6a08cf0, 69448e4, 88e3358, 0bbaa7f, 0582ee7, 89da08b · esg b06fb28, 013f318, 83aaf68, 560da3f, adf9764, 20c8ad9
- What:
  - Handover guide and env examples.
  - Users table SQL.
  - Closed open RLS policies.
  - Removed the unauthenticated admin endpoint.
  - Complaints are no longer lost when AI triage fails.
  - README rewrite.
- Deploy: Supabase SQL (done by Teja), Render

### 2026-11-11 · Teja · Bribery guardrail fix (main only)
- Repos: main b8f4e44 (earlier attempts reverted)
- What: Policy questions about gifts are no longer forced into HIGH bribery complaints.

---

## Known open issues

Move an item into **In progress** when you start on it.

- The chat (`/api/agents/chat`) needs no login and files Medium/High complaints itself, with no owner and no hourly limit. Now that guests see the chatbot (ESG), this is easier to reach; consider applying the guest limit to chat filing.
- Guest limit is per IP: people on the same office Wi-Fi share one complaint per hour, and the limit resets when the backend restarts (ESG).
- A guest can enter someone else's email, and the "complaint received" email goes there (ESG).
- Tracking by a 5-character ID prefix can be guessed.
- Attachment links are public to anyone who has the link.
- The free Groq plan allows only a few dozen chatbot messages a day.
