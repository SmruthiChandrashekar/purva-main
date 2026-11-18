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
### 2026-11-18 · Teja · Safari "Application Error" after a deploy
- Repos: main a4b11bf · esg 544032e
- What: Every deploy renames and deletes the old page code files. In a tab opened before the deploy, Vercel answered requests for the old files with the HTML page. Safari then showed "'text/html' is not a valid JavaScript MIME type", which the reload-once fix didn't recognise (it only knew Chrome and Firefox wording). Now missing /assets/ files return 404, and the Safari wordings also trigger the one automatic reload.
- Files: frontend/vercel.json, frontend/src/utils/newVersionReload.js
- Deploy: Vercel (both)

### YYYY-MM-DD · Who · short title
- Repos: main <commit> · esg <commit>   (or "main only" / "esg only")
- What: one or two plain sentences on what changed and why.
- Files: the main files touched
- Deploy: what has to be redeployed (Vercel / Render / Supabase SQL), or "none"
- Follow-up: anything left open (optional)
```

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

- Guest limit is per IP: people on the same office Wi-Fi share one complaint per hour, and the limit resets when the backend restarts (ESG).
- A guest can enter someone else's email, and the "complaint received" email goes there (ESG).
- Tracking by a 5-character ID prefix can be guessed.
- Attachment links are public to anyone who has the link.
- The free Groq plan allows only a few dozen chatbot messages a day.
