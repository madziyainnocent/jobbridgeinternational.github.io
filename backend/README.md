# JobBridge International — Backend

This folder is the initial backend foundation for the recruitment platform.

## Architecture

- Existing GitHub Pages site: public marketing website and candidate-facing frontend.
- Supabase: Postgres database, Auth, Row Level Security and private candidate-document storage.
- Cloudflare Worker: server-side API, AI chat endpoint and Meta WhatsApp webhook.
- OpenAI Responses API: recruitment FAQ assistant.
- Meta WhatsApp Cloud API: inbound messages and replies.

## 1. Create Supabase project

1. Open https://supabase.com/dashboard and create a project named `jobbridge-international`.
2. Choose a strong database password and store it securely.
3. Open SQL Editor and run `schema.sql`.
4. In Storage, create a **private** bucket named `candidate-documents`.
5. Configure Storage object policies so a signed-in candidate can access only their own folder, while approved staff can access candidate files. Do not make this bucket public.
6. In Authentication > URL Configuration, set the Site URL to `https://jobbridgeinternational.online` and add the production and local callback URLs.
7. Disable public staff-role assignment. Create the first account, then promote it manually using the SQL comment at the end of schema.sql.
8. Copy the Supabase project URL and publishable key for the browser app. Never expose the service-role/secret key.

## 2. Deploy Cloudflare Worker

1. Open https://dash.cloudflare.com and choose Workers & Pages.
2. Create a Worker named `jobbridge-api`.
3. Deploy the contents of `worker/src/index.js` with `worker/wrangler.toml` using Wrangler or the dashboard editor.
4. Add these encrypted secrets under Worker > Settings > Variables and Secrets:
   - `OPENAI_API_KEY`
   - `WHATSAPP_TOKEN`
   - `WHATSAPP_VERIFY_TOKEN`
   - `META_APP_SECRET`
   - `WHATSAPP_PHONE_NUMBER_ID`
5. Set `ALLOWED_ORIGIN` to the exact production website origin.
6. Test `GET https://YOUR-WORKER.workers.dev/api/health` and the chat endpoint.
7. Add a custom API domain such as `api.jobbridgeinternational.online` after deployment.

## 3. OpenAI assistant

Create an API key at https://platform.openai.com/api-keys. Add it only as the Cloudflare Worker secret `OPENAI_API_KEY`. Never put it in GitHub Pages JavaScript, HTML, or a public repository.

The initial assistant answers from a controlled set of public JobBridge facts. Before launch, connect it to published vacancies and authenticated candidate status lookup. The public chatbot must never reveal another applicant's data.

## 4. WhatsApp Cloud API

1. Open https://developers.facebook.com/apps/ and create or select a Meta app.
2. Add the WhatsApp product and connect the JobBridge WhatsApp Business Account and phone number.
3. Configure the webhook URL as `https://YOUR-WORKER.workers.dev/webhooks/whatsapp`.
4. Enter the exact `WHATSAPP_VERIFY_TOKEN` secret as the webhook verify token.
5. Subscribe the app to the `messages` webhook field.
6. Store the permanent access token, App Secret and Phone Number ID as Worker secrets.
7. Complete Meta business verification and production access requirements. Create approved message templates for proactive application notifications.

The webhook verifies Meta's request signature. The starter replies to incoming text messages; production must add deduplication, delivery receipts, opt-out handling, consent records and approved template messages.

## 5. Candidate and staff portal — next implementation stage

The database foundation includes:
- profiles with candidate/staff roles;
- published vacancies;
- applications with unique reference codes;
- application status events;
- candidate document metadata;
- website and WhatsApp conversation logs.

Next frontend work:
- candidate sign-up/sign-in and profile;
- vacancy search and application form;
- private CV/document upload;
- candidate application timeline;
- staff dashboard with role-protected candidate search, vacancy management, screening and status updates;
- notification preferences and WhatsApp opt-in.

## Security and launch checklist

- Test every Row Level Security policy with candidate A, candidate B, recruiter and admin accounts.
- Add Storage object policies before accepting any uploads.
- Add CAPTCHA/Cloudflare Turnstile and rate limiting to public endpoints.
- Add request validation, logging, abuse controls and webhook event deduplication.
- Never put secret keys or private CV URLs in client code.
- Collect explicit consent before WhatsApp messaging; provide an opt-out path.
- Publish privacy, retention and candidate-data handling notices.
- Do not treat AI output as a hiring decision. Recruiters make all selection decisions.

This is an implementation foundation, not a live production recruitment system until the external accounts, secrets, storage policies, frontend and end-to-end tests are completed.
