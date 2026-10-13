---
id: frontend-07-routes-and-cache-components
title: "Routes, layouts and the proxy under Cache Components"
applies_to: frontend
layer: frontend
depends_on:
  - frontend-03-services
  - frontend-04-components
source_files:
  - "apps/web/src/proxy.ts"
  - "apps/web/src/app/[locale]/(main)/layout.tsx"
  - "apps/web/src/app/[locale]/(admin)/layout.tsx"
  - "apps/web/src/features/common/components/session/AppShell.tsx"
  - "apps/web/src/features/common/components/session/requireAdministrator.ts"
  - "apps/web/src/features/common/components/details/LayoutDetails.tsx"
  - "apps/web/src/i18n/navigation.ts"
  - "packages/nextjs-jsonapi/docs/migrating-to-4.0.md"
related_docs:
  - frontend-03-services
  - frontend-04-components
  - anti-patterns
enforcement: critical
last_updated: "2026-10-14"
---

# Routes, layouts and the proxy under Cache Components

## Contents

- WHEN TO USE
- CRITICAL RULES
- ENFORCEMENT CHECKPOINT
- COMMON MISTAKES
- RELATED FILES
- The session shell
- Loading files
- Caching lives on the data
- The build never calls the API
- Administration pages
- The proxy is the login gate
- Links, redirects and locales
- Route handlers
- Metadata
- Verification

---

## WHEN TO USE
Read this file when:
- Adding or editing anything under `apps/web/src/app/**`: a `page.tsx`, a `layout.tsx`, a `loading.tsx`, a `not-found.tsx`, a `route.ts`
- Editing `apps/web/src/proxy.ts`, `apps/web/src/i18n/*`, or a wrapper that sits between a layout and its `{children}` (`AppShell`, `LayoutDetails`)
- Adding a route group, a public path, a sitemap, or a link that carries a locale
- A build fails with "Error occurred prerendering page", or the Navigation Inspector reports "uncached data during a navigation"

Applies to apps on `@carlonicora/nextjs-jsonapi` 4.x with Next 16.4 Cache Components
(`cacheComponents` + `partialPrefetching`, both set by `createNextConfig`). The
library's `docs/migrating-to-4.0.md` is the authority; this file is the rule set.

---

## CRITICAL RULES

1. **Nothing on the path from a layout to `{children}` awaits.** Layouts and shell
   wrappers are synchronous. The session is read once with `ServerSession.read()`
   (never awaited) and the PROMISE goes to `SessionProvider`, `ViewportProvider`,
   `SocketProvider` and `SidebarProvider`. Only leaves unwrap it, with `useSession()`,
   each behind its own `<Suspense>`. The one allowed await is `params` for a segment
   `generateStaticParams` lists (`[locale]`).
2. **One `loading.tsx` per data-fetching segment** — the segment itself, nested ones
   included, not the group or the parent. `PageSkeleton` inside the app frame,
   `SessionFallback` outside it. A static page needs none.
3. **No segment config exports.** `dynamic`, `revalidate`, `fetchCache`,
   `dynamicParams`, `runtime = "edge"` error under Cache Components, re-exports
   included. Never `export const instant = false` to make a build pass.
4. **Caching is declared on the data, not the route.** A module with
   `cache: "<profile or tag>"` routes its GETs through `cachedServerGet` (`"use cache"`,
   token-free). A `cacheLife` profile name sets the life; any other value is a tag
   with `cacheLife("max")`. A per-user endpoint never sets `cache`.
5. **The build never calls the API.** An API read on a prerendered page sits in a
   component that awaits `connection()` behind its own `<Suspense>`. A route handler
   calls `connection()` first. Prove it by building with the API stopped.
6. **Every admin page awaits `requireAdministrator(locale)` as its first statement.**
   The `(admin)` layout reads no session. Non-administrators get `notFound()`, which
   `(admin)/not-found.tsx` renders inside the frame.
7. **The proxy is the login gate.** No layout checks the session and no chrome has a
   logged-out branch. A new top-level public segment goes into `PUBLIC_PATHS`.
8. **Never hand-build `/${locale}/…`.** Link with `Link` from `@/i18n/navigation` and
   locale-free hrefs; build server paths with `getPathname`. With
   `localePrefix: "as-needed"` the proxy redirects `/en/x` to `/x`, and a client
   navigation cannot read page data across that redirect.
9. **A route whose path contains a dot lives outside `[locale]`.** The proxy matcher
   skips dotted paths, so nothing rewrites them to a locale.
10. **A route handler imports `@/config/env` itself.** It renders no layout, so
    nothing else registers the modules for it.
11. **`useSearchParams` / `usePathname` / `useParams` consumers sit behind a
    `<Suspense>`.** In a shared wrapper, move the read into a `null`-rendering leaf
    and keep `{children}` outside that boundary.
12. **Static page metadata passes `path`** to `generateSpecificMetadata` instead of
    letting it read the `x-full-url` header.
13. **No `next/dynamic({ ssr: false })` layouts.** Import the layout statically.
14. **Navigation comes from `@/i18n/navigation`, never `@/i18n/routing`.** The proxy
    imports `routing.ts` only; it must never reach `navigation.ts`
    (`createNavigation` loads `i18n/request.ts`, which reads `next/root-params`).

---

## ENFORCEMENT CHECKPOINT

> **STOP — before saving a file under `apps/web/src/app` or `apps/web/src/proxy.ts`:**
> 1. Is a layout or shell wrapper `async`, or does it `await` the session, cookies or
>    headers? **STOP** — pass `ServerSession.read()` as a promise (rule 1).
> 2. Does the page await data, the session or a permission check, and its own segment
>    has no `loading.tsx`? **STOP** — add one (rule 2).
> 3. Is there an `export const dynamic|revalidate|fetchCache|dynamicParams|runtime`?
>    **STOP** — delete it; put `cache` on the module (rules 3, 4).
> 4. Does a prerendered page or a route handler call the API before `connection()`?
>    **STOP** — move the read into a `connection()` leaf behind `<Suspense>` (rule 5).
> 5. Is it a page under `(admin)` whose first statement is not
>    `await requireAdministrator(locale)`? **STOP** (rule 6).
> 6. Does a string contain `` `/${locale}/ `` or `"/en/"`? **STOP** — `Link` /
>    `getPathname` (rule 8).
> 7. Does a client component call `useSearchParams`/`usePathname` with no
>    `<Suspense>` above it short of the layout's own boundary? **STOP** (rule 11).

---

## COMMON MISTAKES

- `export default async function Layout()` that awaits `ServerSession.isLogged()`
  to branch between a logged-in and a logged-out tree. The proxy already decided;
  delete the branch.
- A single `loading.tsx` on the group, expecting it to cover navigation between
  sibling pages. A client navigation re-renders only below the shared segment.
- `try { await fetchX() } catch {}` around a cached read on a static page. The
  prerender still fails: `cachedServerGet` throws so Next does not store the result,
  and Next fails the page on that throw.
- `export const revalidate = 3600` copied from a pre-4.0 page.
- A `"use cache"` of its own around a route handler's read. The cached path already
  caches, and a local scope would read the locale where root params throw.
- `redirect(`/${locale}/login`)` in a server guard; `href={`/${locale}/help`}` in a
  link; a sitemap emitting `/en/…` URLs.
- `app/[locale]/help/sitemap.xml/route.ts` — answers only at `/en/help/sitemap.xml`.
- A route handler that reads through a module and throws "Module … not registered"
  in `next build`: the `import "@/config/env"` is missing.
- A fixed full-screen overlay (trial expiry, onboarding) in the frame. It hides every
  skeleton. Cover only the content column.
- `Date.now()`, `new Date()` or `Math.random()` during render. The prerender fails,
  silently in a client component, and the whole frame drops out of the shell.
- `useSidebar().isMobile` in the frame; it suspends on the session. Use
  `useSidebarControls()`.

---

## RELATED FILES

| File | When to read |
|------|--------------|
| [03-services.md](03-services.md) | `callApi()` and the module definition that carries `cache` |
| [04-components.md](04-components.md) | Base UI rules for the frame and skeletons |
| [../anti-patterns.md](../anti-patterns.md) | Detection table |
| `packages/nextjs-jsonapi/docs/migrating-to-4.0.md` | The full 4.0 migration recipe and verification scripts |

---

## The session shell

`app/[locale]/(main)/layout.tsx` and `(admin)/layout.tsx` render the same thing:

```tsx
export default function MainLayout(props: { children: React.ReactNode; params: Promise<{ locale: string }> }) {
  const { children } = props;

  return (
    <Suspense fallback={<AppFrameSkeleton />}>
      <AppShell>{children}</AppShell>
    </Suspense>
  );
}
```

`features/common/components/session/AppShell.tsx` is a **synchronous** server component:

```tsx
export function AppShell({ children }: { children: React.ReactNode }) {
  const session = ServerSession.read(); // not awaited

  return (
    <SessionProvider session={session}>
      <ViewportProvider session={session}>
        <SocketProvider session={session}>
          <CurrentUserProvider>
            {/* app providers that do not await */}
            <SidebarProvider session={session}>
              <RefreshUser />
              <LayoutDetails>{children}</LayoutDetails>
            </SidebarProvider>
          </CurrentUserProvider>
        </SocketProvider>
      </ViewportProvider>
    </SessionProvider>
  );
}
```

`LayoutDetails` (client) draws the frame. Every read that suspends is a leaf behind
its own boundary; `{children}` is never inside one:

```tsx
function PageTracker() {
  usePageTracker(); // reads the pathname
  return null;
}

<div data-wrapper className="bg-sidebar flex h-full w-full">
  <Suspense fallback={null}><PageTracker /></Suspense>
  <Suspense fallback={<SidebarSkeleton />}><AppSidebar /></Suspense>
  <div className="flex flex-1 flex-col">
    <TrialBlockingWrapper>{children}</TrialBlockingWrapper>
  </div>
</div>
```

`AppSidebar` is the leaf that unwraps the session:

```tsx
export function AppSidebar() {
  const { isLogged } = useSession(); // suspends: it sits behind <Suspense>
  const router = useRouter();        // from @/i18n/navigation
  useEffect(() => { if (!isLogged) router.replace("/login"); }, [isLogged, router]);
  return <CommonSidebar />;
}
```

| A wrapper between layout and `{children}` reads | Do |
|---|---|
| the pathname or search params | move the read into a `null`-rendering leaf behind `<Suspense fallback={null}>` |
| `useSidebar().isMobile` | `useSidebarControls()` |
| the user state to block (trial expiry) | render `{children}` always; overlay only the content column; redirect from an effect |
| the session to choose a logged-out tree | delete the branch (rule 7) |

A group without the shell that still needs the user (`(auth)`, a public help
centre) wraps its layout in `<Suspense fallback={<SessionFallback />}><CurrentUserProvider>`:
the provider reads the pathname. The public help layout follows rule 1 too: it calls
`ServerSession.read()` and feeds the promise to `SessionProvider` and `SocketProvider`.

Client code that derives from the session promise goes through the library's
adoption pattern (`mapThenable`): a promise passed from server to client arrives as a
wire chunk whose `then()` returns `undefined`.

---

## Loading files

```tsx
// In the app frame: (main), (admin), help segments
import { PageSkeleton } from "@/features/common/components/skeletons/PageSkeleton";

export default function Loading() {
  return <PageSkeleton />;
}
```

```tsx
// Outside the frame: (auth), activation/[code], invitation/[code], reset/[code], oauth/authorize
import { SessionFallback } from "@/features/common/components/session/SessionFallback";

export default function Loading() {
  return <SessionFallback />;
}
```

`SessionFallback` is `<div className="bg-background min-h-screen" />`, and the same
component is the Suspense fallback for groups without the frame. `AppFrameSkeleton`
(`SidebarSkeleton` + `PageSkeleton`) is the fallback of the `(main)` and `(admin)`
layout boundaries. A `loading.tsx` is never `async` and never `"use server"`.

Survey, from `app/[locale]`, of pages with no loading file:

```sh
find . -name page.tsx | sort | while read p; do d=$(dirname "$p"); [ -f "$d/loading.tsx" ] && continue
  a=sync; grep -qE "export default async|await " "$p" && a=ASYNC; printf "%-6s %s\n" "$a" "$d"; done
```

Every `ASYNC` line is a missing `loading.tsx`.

---

## Caching lives on the data

```ts
// `cache: "help"` is not a cacheLife profile → tag "help", cacheLife("max").
const PUBLIC_HOWTO_KEY = { ...Modules.HowTo, cache: "help" };

const res = await ServerJsonApiGet({ classKey: PUBLIC_HOWTO_KEY, endpoint, language });
```

- A server GET whose module has `cache` runs `cachedServerGet`; everything else is a
  plain uncached `fetch`.
- `"seconds" | "minutes" | "hours" | "days" | "weeks" | "max" | "default"` is a
  profile; anything else is a tag. After a write, `invalidateCacheTag(tag)`
  (stale-while-revalidate) or `updateCacheTag(tag)` (a Server Action that must read
  its own write), both from `@carlonicora/nextjs-jsonapi/server`.
- The cache key is the arguments: no token, no cookie, no user id. The request goes
  out without `Authorization`. An endpoint that needs a token does not set `cache`.
- A failing cached call throws; only `error.digest` (`HTTP_<status>`) survives to
  production. Read it with `statusFromDigest`.
- A page with two cached reads runs them in sequence and skips the second when the
  first fails: two failing cached calls in one render never close the response.

---

## The build never calls the API

Docker and CI build with no API reachable. A static page (no params to wait for)
that reads through the cached path is prerendered, so the build makes the call, and
a failed call fails the page.

```tsx
async function FeaturedTutorials() {
  await connection();                       // request time only, never `next build`
  const featured = await fetchPublicHowTos({ howToType: "tutorial" });
  /* … */
}

export default async function HelpLandingPage() {
  const t = await getTranslations();
  return (
    <HelpPageChrome titleType={t("help.landing.heading")}>
      {/* heading and mode links stay in the static shell */}
      <Suspense fallback={null}>
        <FeaturedTutorials />
      </Suspense>
    </HelpPageChrome>
  );
}
```

The read is still cached at run time. A page with `generateStaticParams`
(`/help/[mode]`) is prerendered per param, so it follows the same rule. A cached
page that answers `HTTP_404` at run time: call the API endpoint. "Cannot GET" means
the route is not mounted (public help routes are opt-in:
`bootstrap({ howTo: { publicRoutes: true } })`), a server change.

---

## Administration pages

```tsx
export default async function AdministrationUsersPage(props: { params: Promise<{ locale: string }> }) {
  const { locale } = await props.params;
  await requireAdministrator(locale);

  return <PlatformUsersContainer />;
}
```

```ts
// features/common/components/session/requireAdministrator.ts
export async function requireAdministrator(locale: string): Promise<void> {
  if (!(await ServerSession.isLogged())) redirect(getPathname({ href: "/login", locale }));
  if (!(await ServerSession.hasRole(RoleId.Administrator))) notFound();
}
```

The `(admin)` layout validates the locale (`hasLocale` → `notFound()`) and renders
the shell; it reads nothing else. `(admin)/not-found.tsx` sits under that layout, so
a refused member sees the 404 inside the frame. Every `ServerSession` method except
`read()` awaits cookies: call them in pages and leaves, never in a layout.

---

## The proxy is the login gate

`apps/web/src/proxy.ts`, in order:

1. `stripLocalePrefix` — strips a leading segment only when it is a configured
   locale, and accepts a bare locale (`/en` → `/`).
2. **Refresh first.** With a `refreshToken` and a missing or near-expiry `token`
   (< 300 s), POST `auth/refreshtoken/<refreshToken>`. A failed refresh counts as no
   session, so every decision below sees the real state.
3. No session and not public → redirect to `/login?callbackUrl=<path+query>` and
   clear `token` and `refreshToken`. `callbackUrl` is the name the package's login
   form reads.
4. `createMiddleware(routing)` runs; its response is the one the proxy decorates.
5. No session on `/` → rewrite to `/<locale>/home` (the static landing in
   `(marketing)/home`), URL unchanged. A session with a fresh token → set `token`.
6. `x-full-url` response header for `generateSpecificMetadata`.

```ts
export const PUBLIC_PATHS = ["/", "/home", "/activation", "/auth", "/invitation", "/login",
  "/logout", "/oauth", "/register", "/reset", "/help", "/offline"] as const;

/** `/` matches exactly; every other entry matches itself and anything below it. */
export function isPublicPath(normalizedPathname: string): boolean {
  return PUBLIC_PATHS.some((p) =>
    p === "/" ? normalizedPathname === "/" : normalizedPathname === p || normalizedPathname.startsWith(p + "/"),
  );
}

export const config = { matcher: "/((?!api|trpc|_next|_vercel|.*\\..*).*)" };
```

`PUBLIC_PATHS` mirrors the route groups: `/` and `/home`, every top-level `(auth)`
segment including `/oauth` (the API sends a refused social login to `/oauth/error`
with no session), every public group, and `/offline` (the service worker precaches it
unauthenticated). Never prefix-match `"/"`: it makes every path public. A group
layout that only checked the session is a pass-through; delete it.

---

## Links, redirects and locales

```ts
// apps/web/src/i18n/navigation.ts — never imported by proxy.ts
export const { Link, redirect, usePathname, useRouter, getPathname } = createNavigation(routing);
```

| Need | Use |
|---|---|
| A link | `<Link href="/help/…">` from `@/i18n/navigation` |
| A breadcrumb | a locale-free `href`; the package's `Link` adds the prefix |
| A server redirect / callback URL | `getPathname({ href: "/login", locale })` |
| A canonical URL or sitemap entry | `getPathname({ href, locale: routing.defaultLocale })` — no default-locale prefix |
| Client navigation | `useRouter()` from `@/i18n/navigation`, locale-free path |

`@/i18n/routing` is imported for `routing.locales` / `routing.defaultLocale` data
(root layout, admin layout, sitemap) and by the proxy. Nothing navigates through it.

---

## Route handlers

```ts
// app/help/sitemap.xml/route.ts — outside [locale]: the matcher skips dotted paths
import "@/config/env"; // FIRST: registers the modules; no layout does it here
import { getPathname } from "@/i18n/navigation";
import { routing } from "@/i18n/routing";
import { connection } from "next/server";

export async function GET(req: Request) {
  await connection(); // per request, never during `next build`
  const articles = await fetchPublicHowTos();
  /* getPathname({ href, locale: routing.defaultLocale }) per entry, XML-escaped */
}
```

No `revalidate`, no `"use cache"` of its own: the data is already cached, and
`next/root-params` throws in a route handler. A route that re-exports from
`createSerwistRoute` keeps only `generateStaticParams` and `GET`.

---

## Metadata

```tsx
// (marketing)/home/page.tsx — static: passes `path`, never reads headers
export async function generateMetadata(): Promise<Metadata> {
  const t = await getTranslations();
  return await generateSpecificMetadata({ title: t(`common.home`), path: "/" });
}
```

Without `path`, `generateSpecificMetadata` (`utils/metadata.ts`) awaits `headers()`
for `x-full-url`, which is fine only on a page that already defers to request time.
Static pages pass `path`, auth pages that declare metadata included. A static
component that needs request-time data (a footer's year) awaits `connection()`
inside its own boundary.

---

## Verification

- `pnpm --filter <web> exec next build --debug-prerender` with the API **stopped**.
  App routes list as `◐`; the prerendered HTML of a list and a detail route contains
  the frame markup and the skeleton rows.
- Dev validator findings appear only in *Next.js Dev Tools → Navigation Inspector*,
  not the console. Check every route family, nested segments included, and test a
  client navigation into the route, not only a hard reload.
- Logged out: `/` shows the landing; an app URL goes to login with `callbackUrl`;
  one route per public group loads.

---

**Next**: See [04-components.md](./04-components.md) for the Base UI rules inside the frame.
