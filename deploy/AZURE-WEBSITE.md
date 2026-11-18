# Website on Azure Static Web Apps

This moves the **website** (`frontend/`) from Vercel to **Azure Static Web Apps, Free
plan** (US$0/month). The backend is already on Azure (see `deploy/AZURE.md`).

| What | Name |
|------|------|
| Static Web App (Free) | `purva-main-web`, in resource group `purva-main` |
| Address | `https://<random-name>.azurestaticapps.net` (printed by the setup script) |
| Deploys | `.github/workflows/azure-frontend.yml`, on every push to `main` that changes `frontend/` |
| Login for deploys | the same `purva-main-github` identity as the backend, no stored secrets |

The Free plan serves the site from Microsoft's global edge (fast in India), with free
HTTPS, up to 250 MB of site and 100 GB of traffic a month: far more than this site needs.
Its region (East Asia) is only where its settings are kept.

**Nothing changes for visitors until you switch.** Vercel keeps serving the site the
whole time, and you can test the Azure copy side by side first.

## 1. Supervisor: in Azure Cloud Shell

```bash
cd ~/purva-main && git pull
```

```bash
bash deploy/azure-frontend.sh
```

It creates the Static Web App (if missing) and prints:
- the website's new address,
- one line for the repo owner: `gh variable set AZURE_STATIC_WEB_APP …`.

It also adds the new address to `FRONTEND_URL` in `.env.azure` (after the Vercel address,
so email links keep pointing at Vercel until you switch). Apply that to the backend so it
accepts requests from the new address (CORS):

```bash
bash deploy/azure.sh
```

Rerun either script if Azure answers InternalServerError.

## 2. Whoever has access to Vercel: copy the website's settings

Create a token: Vercel → Account Settings → Tokens. Then, in Cloud Shell or on a Mac:

```bash
read -rs VERCEL_TOKEN && export VERCEL_TOKEN
```
```bash
bash deploy/vercel-env.sh
```

It prints `gh variable set VITE_…` lines for the settings the website is built with
(Supabase address and public key, backend address, two switches). These values are
already public inside the website, so they are not secrets. If the project is in a
Vercel team, add `VERCEL_TEAM_ID=<team id>` in front. Settings marked "sensitive" on
Vercel can't be read back; the script lists them, so copy those from the Vercel
dashboard by hand.

Without a token: Vercel → the project → Settings → Environment Variables, and write the
lines yourself:

```bash
gh variable set VITE_SUPABASE_URL --repo SmruthiChandrashekar/purva-main --body '<value>'
```

Repeat for `VITE_SUPABASE_ANON_KEY`, `VITE_API_BASE_URL` (the Azure backend address, no
trailing slash), and if set on Vercel `VITE_REQUIRE_PHONE_OTP` and `VITE_INTERNAL_EMAIL_DOMAIN`.

## 3. Repo owner (Smruthi)

Run the lines from steps 1 and 2, then the first deploy:

```bash
gh workflow run azure-frontend.yml --repo SmruthiChandrashekar/purva-main
```

Watch it under GitHub → Actions → **Deploy website to Azure**. It builds the site,
uploads it, and checks the live copy: the new version is served, a page link like
`/track` opens the app, a missing code file returns 404, and the site calls the
backend address you set. The run's summary shows the address.

## 4. Test the Azure copy

Open the new address and try: the home page, log in, the chatbot, filing a test
complaint, tracking it, and an admin login. If the browser console shows CORS errors,
`FRONTEND_URL` on the backend doesn't include the new address yet (step 1).

## 5. Switch over

1. **Supabase** → Authentication → URL Configuration:
   - add `https://<new address>/**` to **Redirect URLs** (keep the Vercel one for now),
   - set **Site URL** to `https://<new address>`.
   Password-reset and invite emails link there.
2. **Backend links:** make the new address the first entry of `FRONTEND_URL`, because
   the first entry is used in email links and invites. Edit `.env.azure` in Cloud Shell:
   `FRONTEND_URL="https://<new address>,https://purva-main.vercel.app"`, then
   `bash deploy/azure.sh`.
3. **Tell people the new address.** QR codes and links that point at
   `purva-main.vercel.app` keep going to Vercel for as long as Vercel runs (see below).
4. When nobody uses the Vercel address any more: pause or delete the Vercel project,
   and remove the Vercel address from `FRONTEND_URL` and from Supabase's Redirect URLs.

### The old address and printed QR codes

Moving off Vercel changes the website's address. Anything already printed or shared
(office QR codes, emails, bookmarks) points at `purva-main.vercel.app`. Options:
- **Keep Vercel running** until the QR codes are reprinted. It costs nothing on the free plan,
  but there are then two copies of the site to keep in step.
- **Give the site its own domain** (for example `grm.puravankara.com`). The Free plan
  includes 2 custom domains with HTTPS (Azure portal → the Static Web App → Custom domains).
  Then future moves never change the address again. Needs a DNS record from whoever runs
  the company's domain.

## Changing a website setting later

Change the GitHub Actions variable (GitHub → Settings → Secrets and variables → Actions →
Variables, or `gh variable set …`), then rerun **Deploy website to Azure**. Like on
Vercel, the settings are built into the site, so they only take effect after a new build.

## Removing it

```bash
az staticwebapp delete -n purva-main-web -g purva-main --yes
```

Or `az group delete -n purva-main`, which removes the backend too (see `deploy/AZURE.md`).
