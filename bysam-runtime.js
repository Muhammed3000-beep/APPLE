// BYSAM site arama ve sayfa acma katmani.
// BYSAM ana arayuzune: <script type="module" src="./bysam-runtime.js"></script>
import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

const SUPABASE_URL = 'https://rlncoubbggerpouyxyar.supabase.co';
const SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_pnZXQcnHkb6ZR21SQteS_A_DdxMVrA3';
const BUCKET = 'bysam-sites';
const db = createClient(SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false }
});

/** BYSAM'da tam adres, kisa ad veya site ismi ile yayindaki siteleri bulur. */
export async function searchSites(term, limit = 12) {
  const query = String(term ?? '').trim();
  if (!query) return [];

  const exactDomain = query.toLowerCase();
  const { data: byDomain, error: domainError } = await db
    .from('bysam_sites')
    .select('id,site_name,slug,domain_extension,domain,description,status')
    .eq('status', 'published')
    .eq('domain', exactDomain)
    .limit(1);
  if (domainError) throw domainError;
  if (byDomain?.length) return byDomain;

  const normalizedSlug = query.toLowerCase().replace(/\.(bysam|bysm|kızmalımı|etmez|upset|siber|bry|beray|xmax)$/i, '');
  const { data: bySlug, error: slugError } = await db
    .from('bysam_sites')
    .select('id,site_name,slug,domain_extension,domain,description,status')
    .eq('status', 'published')
    .eq('slug', normalizedSlug)
    .limit(1);
  if (slugError) throw slugError;
  if (bySlug?.length) return bySlug;

  const safeTerm = query.replace(/[,%()]/g, ' ').trim();
  const { data, error } = await db
    .from('bysam_sites')
    .select('id,site_name,slug,domain_extension,domain,description,status')
    .eq('status', 'published')
    .ilike('site_name', `%${safeTerm}%`)
    .order('site_name', { ascending: true })
    .limit(Math.max(1, Math.min(Number(limit) || 12, 50)));
  if (error) throw error;
  return data ?? [];
}

/** Bir sitenin yayinlanmis index.html dosyasinin herkese acik adresini dondurur. */
export async function getSiteEntryUrl(siteOrId, { allowDraft = false } = {}) {
  const siteId = typeof siteOrId === 'string' ? siteOrId : siteOrId?.id;
  if (!siteId) throw new Error('Site kimligi gerekli.');
  let siteQuery = db
    .from('bysam_sites')
    .select('id,site_name,domain,status')
    .eq('id', siteId);
  if (!allowDraft) siteQuery = siteQuery.eq('status', 'published');
  const { data: site, error: siteError } = await siteQuery.single();
  if (siteError) throw siteError;

  const { data: file, error: fileError } = await db
    .from('bysam_site_files')
    .select('storage_path')
    .eq('site_id', siteId)
    .eq('file_path', 'index.html')
    .maybeSingle();
  if (fileError) throw fileError;
  if (!file) throw new Error('Bu site icin index.html bulunamadi.');

  const { data } = db.storage.from(BUCKET).getPublicUrl(file.storage_path);
  return { site, url: data.publicUrl };
}

/**
 * HTML belgesini, kaynak dosyanin Storage klasorunu temel alarak iframe icinde calistirir.
 * HTML dosyasi Storage tarafinda text/plain veya octet-stream donse bile srcdoc HTML olarak yorumlanir.
 * allow-same-origin bilerek verilmez: yayinlanan site BYSAM arayuzunun oturumuna erisemez.
 */
export function renderHtmlIntoFrame(source, sourceUrl, frame) {
  if (!(frame instanceof HTMLIFrameElement)) throw new Error('Gecerli bir iframe gerekli.');
  const htmlSource = String(source ?? '');
  if (!htmlSource.trim()) throw new Error('HTML dosyasi bos.');

  const parsed = new DOMParser().parseFromString(htmlSource, 'text/html');
  // CSS, JS ve gorsel gibi goreli yollar dosyanin depolandigi site klasorune cozulur.
  const base = parsed.createElement('base');
  base.href = new URL('.', sourceUrl).href;
  parsed.head.insertBefore(base, parsed.head.firstChild);

  frame.setAttribute('sandbox', 'allow-scripts allow-forms allow-popups allow-modals allow-downloads allow-presentation');
  frame.referrerPolicy = 'no-referrer';
  frame.loading = 'eager';
  frame.srcdoc = '<!doctype html>\n' + parsed.documentElement.outerHTML;
  return frame;
}

/** Yayindaki index.html dosyasini indirir ve gercek HTML sayfasi olarak iframe'de calistirir. */
export async function renderSiteIntoFrame(siteOrId, frame, options = {}) {
  const { site, url } = await getSiteEntryUrl(siteOrId, options);
  const response = await fetch(url, { method: 'GET', cache: 'no-store' });
  if (!response.ok) throw new Error(`Site dosyasi alinamadi (HTTP ${response.status}).`);
  const source = await response.text();
  renderHtmlIntoFrame(source, url, frame);
  return { site, url, frame };
}

/** BYSAM'da secilen siteyi kapsayici icinde acar. */
export async function mountSite(term, container) {
  if (!(container instanceof Element)) throw new Error('Siteyi gostermek icin bir HTML kapsayicisi gerekli.');
  const matches = await searchSites(term, 1);
  if (!matches.length) throw new Error('Bu adla yayinlanmis BYSAM sitesi bulunamadi.');
  const frame = document.createElement('iframe');
  frame.title = matches[0].site_name;
  frame.style.cssText = 'display:block;width:100%;height:100%;min-height:600px;border:0;border-radius:14px;background:#fff';
  container.replaceChildren(frame);
  const result = await renderSiteIntoFrame(matches[0], frame);
  return { ...result, frame };
}

// Ana arayuz isterse tek isim altindan cagirsin.
export const BYSAM = { searchSites, getSiteEntryUrl, renderHtmlIntoFrame, renderSiteIntoFrame, mountSite };
if (typeof window !== 'undefined') window.BYSAM = BYSAM;
