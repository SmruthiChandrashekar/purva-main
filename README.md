# Puravankara Grievance Redressal Mechanism (GRM): all departments

A web portal where employees, contract workers and external stakeholders (homebuyers,
residents, vendors) file grievances, ask a policy chatbot questions, and track their
complaints, while staff work through the complaints in tiered queues with SLA deadlines.

- **Live test site:** https://purva-main.vercel.app/
- **This app** routes each complaint to one of six departments. The sister app
  [purva-esg](https://github.com/SmruthiChandrashekar/purva-esg) is the same code base
  with every complaint sent to ESG.
- **Handing it over or hosting it elsewhere?** Read [HANDOVER.md](HANDOVER.md).

## What it does

| Area | Details |
|------|---------|
| **Filing** | Three stakeholder forms (Internal employee, Contract worker, External stakeholder), file attachments, anonymous filing, incident date (no future dates) |
| **AI triage** | An LLM (Groq, `qwen/qwen3.8-27b`) sets severity (Low / Medium / High) and department (HR, IC, CRM, CSD, ESG, Investors). Keyword rules force High for POSH, site-safety and real bribery reports. For a Low complaint the form first shows the policy answer, with **File it anyway** to file it at L1 without retyping; if the AI is unavailable the complaint is filed as Medium. |
| **Routing and SLA** | Medium starts at L1, High at L2. Tier deadlines: L1 48 h, L2 24 h, L3 12 h, HEAD 4 h. A background monitor checks every 5 minutes and escalates overdue complaints L1 → L2 → L3 → HEAD. Resolution deadlines follow working-day rules (`sla_policies`) and the holiday calendar (`holidays`). |
| **Policy chatbot ("Purva")** | Answers from ~40 company policy documents using hybrid search (BM25 keywords + vector meaning-based search, merged). Turns complaint-like messages into a filing with the right severity and department. |
| **Tracking** | Anyone with a complaint ID (first 5+ characters) sees its status, deadline and documents shared with them. Logged-in users see their own complaints on a dashboard. |
| **Staff** | Admin dashboard (queue, charts, status updates, maker-checker rejection), in-app notifications, email alerts. Super admins invite staff, set tiers, deactivate accounts and read the audit log. |
| **Other** | UI in English, Hindi and Kannada; voice input (Groq `whisper-large-v3`); optional phone verification by SMS; light and dark theme; works on phones. |

## How it fits together

```
 Browser (React app on Vercel)
   │  login, own profile, file uploads ──────────────► Supabase (Postgres, Auth, Storage)
   │  everything else (REST) ──► Backend (FastAPI on Render) ──► Supabase (service key)
   │                                │
   │                                ├──► Groq API: triage, chatbot answers, voice
   │                                ├──► Embedding Space (Hugging Face): vectors for policy search
   │                                └──► Brevo: email
```

## Repository layout

```
├── backend/
│   ├── main.py                FastAPI app: every API route, startup, SLA monitor start
│   ├── agent/                 LangGraph chatbot/triage graph (graph.py, nodes/, edges/, llm.py)
│   ├── config/categories.py   Departments, categories, POSH/safety keywords
│   ├── middleware/auth.py     Supabase login check, roles (user / admin / super_admin)
│   ├── sla/                   Resolution SLA: working days, holidays, deadlines
│   ├── utils/                 SLA monitor, notifications, audit log, translation, phone OTP, PDF reports
│   ├── database/              SQL to build the Supabase database (see its README.md)
│   ├── tests/                 pytest suite (offline, with fakes)
│   ├── bootstrap_super_admin.py   One-time script: first super admin and department staff logins
│   └── .env.example           Backend settings, each marked [REQUIRED] or [OPTIONAL]
├── agents/
│   ├── escalation/            Email (Brevo or SMTP) and SMS notifier, escalation agent
│   └── intent/                Intent helper
├── rag/
│   ├── query_data.py          Hybrid policy search, embedding-service client
│   ├── policy_indexer.py      BM25 index, built in memory at startup
│   ├── policy_recommender.py  Policy suggestions attached to complaints
│   ├── data/okf_policies/     The policy documents (markdown) that are searched
│   └── chroma_final/          Prebuilt vector index (all-MiniLM-L6-v2), committed
├── frontend/                  React 19 + Vite 7 + Bootstrap website
│   ├── src/pages/             One file per page (Lodge*, Track, Dashboard, AdminDashboard, ...)
│   ├── src/components/        Navbar, Chatbot, NotificationDropdown, FileUpload, ...
│   ├── src/services/          API client and Supabase client
│   ├── public/locales/        UI text in en / hi / kn
│   ├── vercel.json            Single-page-app rewrite for Vercel
│   └── .env.example           Website settings (all public, built in)
├── deploy/hf-embed-space/     The embedding service (Gradio app for Hugging Face Spaces)
├── render.yaml                Render blueprint for the backend
├── requirements.txt           Python dependencies for the backend (light: no PyTorch)
├── .github/workflows/         keep-render-awake.yml (pings /health every 10 minutes)
└── HANDOVER.md                What to host and how, for a new team
```

## Run it locally from a fresh clone

### 1. What you need

| Tool / account | Version / notes |
|----------------|-----------------|
| Python | **3.11** (the version Render uses: 3.11.11) |
| Node.js | **20.19+ or 22.12+** (needed by Vite 7) |
| Supabase project | Free plan is enough for testing |
| Groq API key | https://console.groq.com |
| Optional | Hugging Face account (embedding Space), Brevo account (email), Twilio (SMS) |

### 2. Database

Create a Supabase project, then follow [backend/database/README.md](backend/database/README.md):
run the SQL files in the listed order in the SQL Editor, check row-level security, and set
the Auth URLs (`http://localhost:5173` for local work).

### 3. Backend

Run everything from the **repository root** (Python imports `backend`, `agents` and `rag`
as packages).

```bash
python3.11 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp backend/.env.example backend/.env
```

Fill in `backend/.env`. To start you need `SUPABASE_URL`, `SUPABASE_KEY` (anon key),
`SUPABASE_SERVICE_ROLE_KEY`, `GROQ_API_KEY` and `FRONTEND_URL=http://localhost:5173`.
Every other setting is described in the file.

```bash
uvicorn backend.main:app --reload --port 8000
```

Check it: http://localhost:8000/health should return `"status": "healthy"` and, after a few
seconds, `"rag_ready": true`.

**Policy search on your machine:** without `EMBED_URL` the backend uses keyword (BM25)
search only. For full hybrid search either set `EMBED_URL`, `EMBED_KEY` and `HF_TOKEN`
(see [deploy/hf-embed-space/README.md](deploy/hf-embed-space/README.md)), or install the
model locally: `pip install sentence-transformers` (pulls in PyTorch, about 1 GB). The backend uses a local model first when it finds one.

### 4. First admin accounts

```bash
python backend/bootstrap_super_admin.py
```

With `SUPER_ADMIN_EMAIL`, `SUPER_ADMIN_PASSWORD` and `SEED_ADMIN_PASSWORD` set in
`backend/.env`, this creates the super admin and one staff login per department and tier
(L1, L2, L3, HEAD). Remove the three values afterwards. More staff are invited from the
Super Admin page (needs email configured).

### 5. Website

```bash
cd frontend
npm ci
cp .env.example .env               # set VITE_SUPABASE_URL, VITE_SUPABASE_ANON_KEY,
                                   # VITE_API_BASE_URL=http://localhost:8000
npm run dev
```

Open http://localhost:5173. Other scripts: `npm run build` (output in `frontend/dist`),
`npm run preview`, `npm run lint`.

## Tests

```bash
pip install pytest
python -m pytest backend/tests -q \
  --deselect backend/tests/test_agent.py \
  --deselect backend/tests/test_multiturn_condensation.py
```

These run offline: Supabase, email and the AI are replaced with fakes, so no `.env` or keys
are needed. The two left out (`test_agent.py`, `test_multiturn_condensation.py`) call the
real Groq API and need `GROQ_API_KEY`; their results vary with the model.
`evaluate_*.py` and `run_all_metrics.py` in `backend/tests/` are evaluation scripts, not tests.

## Deployment (current setup)

| Part | Host | Config |
|------|------|--------|
| Website | Vercel | Root directory `frontend`, build `npm run build`, output `dist`, settings from `frontend/.env.example`. `vercel.json` handles page routes. |
| Backend | Render (web service) | [render.yaml](render.yaml): `pip install -r requirements.txt`, `uvicorn backend.main:app --host 0.0.0.0 --port $PORT`, health check `/health`. Fits the free 512 MB plan. |
| Embedding service | Hugging Face Space (ZeroGPU) | [deploy/hf-embed-space](deploy/hf-embed-space). The backend needs `EMBED_URL`, `EMBED_KEY` **and** `HF_TOKEN`; without the token, calls fail on the anonymous GPU quota and search silently drops to keywords only. |
| Database, logins, files | Supabase | [backend/database/README.md](backend/database/README.md) |
| Keep-awake | GitHub Actions or any cron | Free Render services sleep after 15 idle minutes; ping `/health` every 10 minutes. The workflow needs the repo variable `RENDER_BACKEND_URL`. |

After changing backend code, check Render deployed the new commit (Render → service → Events).

### Free-plan limits

The free plans are fine for testing, not for production. The first limit reached is the AI:
Groq's free limits for this model (8K tokens/minute, 200K tokens/day) cover only a few
dozen chatbot messages a day, since each message makes about 3 AI calls (~3K tokens). Brevo's
free plan sends 300 emails a day, Supabase's free plan allows 5 GB of data out per month, and
Vercel's Hobby plan is for non-commercial use. Production needs paid plans for these.

## Known limitations

- Attachments are stored in a public Supabase bucket: anyone with a file's link can open it
  (they cannot be listed).
- Translation of complaint text uses Google Translate through `deep-translator` and can be
  rate-limited; the UI text itself is static and always works.
- `backend/requirements.txt` is an older, different list. Use the root `requirements.txt`.
- The vector index (`rag/chroma_final`) is prebuilt and committed. The script that builds it
  (`rag/create_database.py`) is in the research repo and in purva-esg, not here; rebuild it
  only if the policy documents change.

## Related repositories

| Repo | What it is |
|------|------------|
| [purva-main](https://github.com/SmruthiChandrashekar/purva-main) | This app (all departments), deployment copy |
| [purva-esg](https://github.com/SmruthiChandrashekar/purva-esg) | ESG-only variant |
| [minor](https://github.com/SmruthiChandrashekar/minor) | Full research code: local ML models, experiments, paper |
