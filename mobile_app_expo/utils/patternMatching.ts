/**
 * Serial/part number extraction – same logic as iOS ScannerViewModel.
 * Uses same patterns: P/N suffix, labeled same-line, multi-line label+value, score-based fallback.
 * Includes OCR normalization and common misread fixes for EasyOCR output.
 */

const DASH_VARIANTS = ['−', '–', '—', '―'];

function normalizeDashes(s: string): string {
  let out = s;
  for (const d of DASH_VARIANTS) out = out.replace(new RegExp(d, 'g'), '-');
  return out;
}

/** Collapse multiple spaces and trim (OCR often adds extra spaces). */
function normalizeOCRSpaces(s: string): string {
  return s.replace(/\s+/g, ' ').trim();
}

/**
 * Fix common EasyOCR misreads in serial/part codes: O↔0, l/I↔1, S↔5 in digit context.
 * Only applied to strings that already look like alphanumeric codes.
 */
function fixCommonOCRErrors(value: string): string {
  if (!value || value.length < 4) return value;
  const cleaned = value.replace(/\s/g, '');
  if (!/^[A-Za-z0-9\-\.]+$/.test(cleaned)) return value;
  let out = cleaned;
  // In serial/part codes, letter O is often misread as 0 and vice versa. Prefer digit 0 when surrounded by digits.
  out = out.replace(/(\d)O(\d)/g, '$10$2'); // O between digits -> 0
  out = out.replace(/^O(\d)/, '0$1').replace(/(\d)O$/, '$10'); // O at start/end next to digit
  // Lowercase l and uppercase I misread as 1 in digit context
  out = out.replace(/(\d)[lI](\d)/g, '$11$2').replace(/(\d)[lI]$/, '$11').replace(/^[lI](\d)/, '1$1');
  return out;
}

function cleanLine(line: string): string {
  const trimmed = normalizeOCRSpaces(line);
  return normalizeDashes(trimmed.toUpperCase());
}

function isAlphanumericCode(text: string): boolean {
  const cleaned = text.replace(/\s/g, '');
  const hasLetter = /[A-Za-z]/.test(cleaned);
  const hasNumber = /[0-9]/.test(cleaned);
  const isClean = /^[A-Za-z0-9\-\.]+$/.test(cleaned);
  return (hasLetter || hasNumber) && isClean;
}

const LABELS = new Set([
  'SER', 'SERIAL', 'SERIAL N°', 'SERIAL NO', 'SERIAL NUMBER',
  'PNR', 'P/N', 'PN', 'PNF', 'PART', 'PART NO', 'PART NUMBER',
  'MFR', 'MODEL', 'MDL', 'REF', 'DATE', 'DOM',
  'N°MATRICULE', 'MATRICULE', 'CONTROLE', 'INSPECTION',
  'SUPPORT', 'ACCESSORY', 'GEARBOX',
]);

function isLabelLine(text: string): boolean {
  return LABELS.has(text.toUpperCase());
}

const NOISE_PATTERNS = [
  'PREVIEW', 'FILE', 'EDIT', 'VIEW', 'GO', 'TOOLS', 'WINDOW', 'HELP',
  '.JPG', '.PNG', '.PDF', 'TV', 'Q Q', '0,',
  'MFR ', 'BIRMINGHAM', 'ENGLAND', 'USA', 'INC.', 'LTD',
  'MAIN HEAT', 'EXCHANGER', 'AVIATION', 'INSP',
  'EID ', 'IMEI', 'MEID', 'IMEI2', 'IMEI/MEID',
  'MFF', 'METERING UNIT', 'DMI', 'FAB', 'ASSY', 'PAT', 'US PAT',
];

function isNoiseLine(text: string): boolean {
  if (text.length <= 3) return true;
  const upper = text.toUpperCase();
  for (const noise of NOISE_PATTERNS) {
    if (upper === noise || upper.startsWith(noise + ' ') || upper.endsWith(' ' + noise))
      return true;
  }
  if (upper.endsWith('.JPG') || upper.endsWith('.PNG') || upper.includes('...')) return true;
  return false;
}

function extractFirstCode(text: string): string {
  const normalized = normalizeDashes(text);
  const match = normalized.match(/^([A-Z0-9][A-Z0-9\-.]*[A-Z0-9])/i);
  if (match) return stripTrailingJunk(match[1]);
  const first = (normalized.split(/\s+/)[0] ?? normalized).replace(/\/+$/, '');
  return stripTrailingJunk(first);
}

/** Remove trailing slashes and other non-code characters from extracted value. */
function stripTrailingJunk(s: string): string {
  return s.replace(/[\s\/,;:]+$/, '').trim();
}

function extractSerialWithOptionalPrefix(line: string): string | null {
  const re = /^\(?\s*[Ss]\s*\)?\s*[Ss]erial\s*[Nn]o\.?\s*[:\s]*([A-Z0-9]+(?:[-/][A-Z0-9]+)?)/i;
  const m = line.match(re);
  if (!m || m[1].length < 4) return null;
  const value = m[1].trim();
  return isAlphanumericCode(value) ? value : null;
}

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function extractWithWordBoundary(line: string, prefix: string): string | null {
  const pattern = new RegExp('^' + escapeRegex(prefix) + '[\\s:]+(.+)$', 'i');
  const m = line.match(pattern);
  if (!m) return null;
  const value = extractFirstCode(m[1].trim());
  if (value.length >= 4 && isAlphanumericCode(value)) return value;
  return null;
}

/** Find a label anywhere in the line and return the code after it (for "X SER WYGP9204" style). */
function extractAfterLabel(line: string, labels: string[]): string | null {
  const upper = line.toUpperCase();
  for (const label of labels) {
    const idx = upper.indexOf(label.toUpperCase());
    if (idx === -1) continue;
    const after = line.slice(idx + label.length).replace(/^[\s:]+/, '');
    const code = extractFirstCode(after);
    if (code.length >= 4 && isAlphanumericCode(code)) return code;
  }
  return null;
}

function serialNumberScore(text: string): number {
  let score = 0;
  const length = text.length;
  if (length < 5 || length > 30) return 0;
  if (/^[0-9]+\/?$/.test(text.replace(/\s/g, ''))) return 0;
  if (text.endsWith('/')) return 0;
  const alphanumericCount = (text.match(/[A-Za-z0-9\-.]/g) || []).length;
  if (alphanumericCount / length < 0.8) return 0;
  if (/[A-Za-z]/.test(text)) score += 2;
  if (/[0-9]/.test(text)) score += 2;
  if (/[A-Za-z]/.test(text) && /[0-9]/.test(text)) score += 5;
  if (length >= 8 && length <= 20) score += 3;
  if (text.includes('-')) score += 2;
  const commonWords = ['MODEL', 'SERIAL', 'PART', 'NUMBER', 'TYPE', 'MADE', 'DATE'];
  if (commonWords.includes(text.toUpperCase())) return 0;
  const deviceIds = ['EID', 'IMEI', 'MEID', 'IMEI2', 'IMEI/MEID'];
  for (const id of deviceIds) {
    if (text.toUpperCase().startsWith(id)) return 0;
  }
  const digitCount = (text.match(/[0-9]/g) || []).length;
  if (digitCount > 20) return 0;
  return score;
}

export interface ExtractedResult {
  serialNumber: string | null;
  partNumber: string | null;
}

/**
 * Extract serial and part number from OCR text lines (same logic as iOS).
 * Input lines are normalized (spaces, dashes); extracted values get common OCR fixes.
 */
export function extractSerialAndPartNumber(textLines: string[]): ExtractedResult {
  let serialNumber: string | null = null;
  let partNumber: string | null = null;

  const cleanedLines = textLines
    .map((line) => normalizeOCRSpaces(line))
    .filter((line) => line.length > 0)
    .map((line) => cleanLine(line));

  // Step 1: Lines ending with P/N
  for (const line of cleanedLines) {
    const trimmed = line.trim();
    if (partNumber == null && trimmed.endsWith('P/N')) {
      const codepart = trimmed
        .replace(/P\/N/g, '')
        .trim()
        .replace(/\/S-M/g, '')
        .trim();
      if (codepart.length >= 5 && isAlphanumericCode(codepart.replace(/\s/g, ''))) {
        partNumber = codepart;
      }
    }
  }

  // Step 2: Same-line labeled values (prefix at start)
  for (const line of cleanedLines) {
    const trimmed = line.trim();
    if (trimmed.length < 3 || isNoiseLine(trimmed)) continue;
    if (trimmed.endsWith('P/N')) continue;

    if (serialNumber == null) {
      const v =
        extractSerialWithOptionalPrefix(trimmed) ??
        extractWithWordBoundary(trimmed, 'SERIAL NO') ??
        extractWithWordBoundary(trimmed, 'SERIAL NUMBER') ??
        extractWithWordBoundary(trimmed, 'SERIAL') ??
        extractWithWordBoundary(trimmed, 'SER') ??
        extractWithWordBoundary(trimmed, 'S/N') ??
        extractWithWordBoundary(trimmed, 'SN');
      if (v) serialNumber = v;
    }
    if (partNumber == null) {
      const v =
        extractWithWordBoundary(trimmed, 'PNR') ??
        extractWithWordBoundary(trimmed, 'PNF') ??
        extractWithWordBoundary(trimmed, 'P/N') ??
        extractWithWordBoundary(trimmed, 'PN') ??
        extractWithWordBoundary(trimmed, 'PART');
      if (v) partNumber = v;
    }
  }

  // Step 2b: Label anywhere in line (e.g. "WOODWARD SER WYGP9204" or "MFF 07482 SER WYGP9204")
  if (serialNumber == null || partNumber == null) {
    for (const line of cleanedLines) {
      const trimmed = line.trim();
      if (trimmed.length < 6) continue;
      if (serialNumber == null) {
        const v =
          extractAfterLabel(trimmed, ['SER', 'S/N', 'SN', 'SERIAL']) ??
          extractAfterLabel(trimmed, ['SERIAL NO', 'SERIAL NUMBER']);
        if (v) serialNumber = v;
      }
      if (partNumber == null) {
        const v = extractAfterLabel(trimmed, ['PNF', 'P/N', 'PN', 'PART NO', 'PART NUMBER', 'PART']);
        if (v) partNumber = v;
      }
    }
  }

  // Step 3: Multi-line (label on one line, value on next)
  const serialLabels = [
    'SER', 'S/N', 'SN', 'SERIAL', 'SERIAL NO', 'SERIAL NUMBER',
    'SERIAL N°', 'SERIAL N', 'N°MATRICULE', 'MATRICULE',
  ];
  const partLabels = ['PNR', 'P/N', 'PN', 'PNF', 'PART', 'PART NO', 'PART NUMBER'];

  for (let i = 0; i < cleanedLines.length; i++) {
    const trimmed = cleanedLines[i].trim();
    const isSerialLabel = serialLabels.some((l) => trimmed === l || trimmed.startsWith(l + ':') || trimmed.startsWith(l + ' '));
    const isPartLabel = partLabels.some((l) => trimmed === l || trimmed.startsWith(l + ':') || trimmed.startsWith(l + ' '));
    if (serialNumber == null && isSerialLabel) {
      const next = cleanedLines[i + 1]?.trim();
      if (next && next.length >= 4 && !isLabelLine(next)) {
        const code = extractFirstCode(next);
        if (code.length >= 4 && isAlphanumericCode(code)) serialNumber = code;
      }
    }
    if (partNumber == null && isPartLabel) {
      const next = cleanedLines[i + 1]?.trim();
      if (next && next.length >= 4 && !isLabelLine(next)) {
        const code = extractFirstCode(next);
        if (code.length >= 4 && isAlphanumericCode(code)) partNumber = code;
      }
    }
  }

  // Step 4: Score-based fallback for serial
  if (serialNumber == null) {
    const candidates: [string, number][] = [];
    for (const line of cleanedLines) {
      const trimmed = line.trim();
      if (isNoiseLine(trimmed) || isLabelLine(trimmed)) continue;
      if (trimmed.includes('P/N')) continue;
      if (partNumber && trimmed.includes(partNumber)) continue;
      const score = serialNumberScore(trimmed);
      if (score > 0) candidates.push([trimmed, score]);
    }
    candidates.sort((a, b) => b[1] - a[1]);
    if (candidates.length > 0) serialNumber = candidates[0][0];
  }

  // Apply common OCR error fixes and strip trailing junk
  if (serialNumber) {
    serialNumber = fixCommonOCRErrors(stripTrailingJunk(serialNumber));
    if (serialNumber === '-' || serialNumber.length < 4) serialNumber = null;
  }
  if (partNumber) {
    partNumber = fixCommonOCRErrors(stripTrailingJunk(partNumber));
    if (partNumber === '-' || partNumber.length < 4) partNumber = null;
  }

  return { serialNumber, partNumber };
}
