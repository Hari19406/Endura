// Syncs the AIMS (Association of International Marathons and Distance Races)
// public ICS calendar feed into the `races` table.
//
// Feed format is RFC 5545 iCalendar: VEVENT blocks with folded continuation
// lines (a line starting with a space continues the previous line). AIMS
// gives us UID/SUMMARY/DTSTART/DTEND/LOCATION/URL/ORGANIZER — no structured
// distance field, and LOCATION is sometimes "City, Country", sometimes just
// "Country". Both are parsed best-effort rather than assumed clean.

import { createClient } from "npm:@supabase/supabase-js@2";

const AIMS_FEED_URL = "https://aims-worldrunning.org/events.ics";

interface ParsedEvent {
  source_uid: string;
  name: string;
  race_date: string;
  race_end_date: string | null;
  location_raw: string | null;
  city: string | null;
  country: string | null;
  distance_label: string | null;
  registration_url: string | null;
  organizer: string | null;
}

function unfoldIcs(raw: string): string[] {
  const rawLines = raw.split(/\r\n|\n|\r/);
  const lines: string[] = [];
  for (const line of rawLines) {
    if ((line.startsWith(" ") || line.startsWith("\t")) && lines.length > 0) {
      lines[lines.length - 1] += line.slice(1);
    } else {
      lines.push(line);
    }
  }
  return lines;
}

function unescapeIcsText(value: string): string {
  return value
    .replace(/\\n/gi, "\n")
    .replace(/\\,/g, ",")
    .replace(/\\;/g, ";")
    .replace(/\\\\/g, "\\")
    .trim();
}

function parseIcsDate(value: string): string {
  // AIMS dates are all-day, formatted YYYYMMDD.
  const m = value.match(/^(\d{4})(\d{2})(\d{2})/);
  if (!m) throw new Error(`Unparseable ICS date: ${value}`);
  return `${m[1]}-${m[2]}-${m[3]}`;
}

function guessDistanceLabel(name: string): string | null {
  const n = name.toLowerCase();
  if (n.includes("half marathon") || n.includes("half-marathon")) return "Half Marathon";
  if (n.includes("marathon")) return "Marathon";
  if (n.includes("ultra")) return "Ultra";
  if (/\b10\s?k\b/.test(n)) return "10K";
  if (/\b5\s?k\b/.test(n)) return "5K";
  return null;
}

function splitLocation(location: string | null): { city: string | null; country: string | null } {
  if (!location) return { city: null, country: null };
  const parts = location.split(",").map((p) => p.trim()).filter(Boolean);
  if (parts.length >= 2) {
    return { city: parts.slice(0, -1).join(", "), country: parts[parts.length - 1] };
  }
  if (parts.length === 1) {
    return { city: null, country: parts[0] };
  }
  return { city: null, country: null };
}

// AIMS's LOCATION field is very often just "India" with no city — but the
// race NAME itself almost always names the host city ("Tata Mumbai
// Marathon", "Run Bhopal Run"). Used only as a fallback when splitLocation
// couldn't find a city and the country resolved to India. Matches are
// deliberately specific (known race-name patterns), not a guess from any
// city substring, to avoid misattributing a race to the wrong place.
const INDIA_CITY_NAME_PATTERNS: [RegExp, string][] = [
  [/delhi half marathon/i, "Delhi"],
  [/tawang marathon/i, "Tawang"],
  [/kashmir marathon/i, "Srinagar"],
  [/trivandrum marathon/i, "Trivandrum"],
  [/kolkata marathon/i, "Kolkata"],
  [/run bhopal run/i, "Bhopal"],
  [/pune international marathon/i, "Pune"],
  [/indore marathon/i, "Indore"],
  [/chennai marathon/i, "Chennai"],
  [/durgapur marathon/i, "Durgapur"],
  [/mumbai marathon/i, "Mumbai"],
  [/vadodara international marathon/i, "Vadodara"],
  [/amdavad marathon/i, "Ahmedabad"],
  [/bodhgaya marathon/i, "Bodh Gaya"],
  [/world 10k bengaluru/i, "Bengaluru"],
  [/spiti marathon/i, "Spiti Valley"],
  [/sohra international half marathon/i, "Sohra"],
  [/hyderabad marathon/i, "Hyderabad"],
  [/goa river marathon|goa marathon/i, "Goa"],
  [/jaipur marathon/i, "Jaipur"],
  [/lucknow marathon/i, "Lucknow"],
  [/nagpur marathon/i, "Nagpur"],
  [/coimbatore marathon/i, "Coimbatore"],
  [/surat marathon/i, "Surat"],
  [/bhubaneswar marathon/i, "Bhubaneswar"],
  [/guwahati marathon/i, "Guwahati"],
  [/chandigarh marathon/i, "Chandigarh"],
  [/kochi marathon/i, "Kochi"],
  [/vizag marathon|visakhapatnam marathon/i, "Visakhapatnam"],
  [/nashik marathon/i, "Nashik"],
  [/rajkot marathon/i, "Rajkot"],
  [/amritsar marathon/i, "Amritsar"],
  [/agra marathon/i, "Agra"],
  [/varanasi marathon/i, "Varanasi"],
  [/mysore marathon|mysuru marathon/i, "Mysuru"],
  [/bengaluru marathon|bangalore marathon/i, "Bengaluru"],
];

function guessIndiaCityFromName(name: string): string | null {
  for (const [pattern, city] of INDIA_CITY_NAME_PATTERNS) {
    if (pattern.test(name)) return city;
  }
  return null;
}

function parseEvents(icsText: string): ParsedEvent[] {
  const lines = unfoldIcs(icsText);
  const events: ParsedEvent[] = [];
  let current: Record<string, string> | null = null;

  for (const line of lines) {
    if (line === "BEGIN:VEVENT") {
      current = {};
      continue;
    }
    if (line === "END:VEVENT") {
      if (current) {
        try {
          events.push(toParsedEvent(current));
        } catch (_err) {
          // Skip malformed events rather than failing the whole sync.
        }
      }
      current = null;
      continue;
    }
    if (!current) continue;

    const colonIdx = line.indexOf(":");
    if (colonIdx === -1) continue;
    const rawKey = line.slice(0, colonIdx);
    const key = rawKey.split(";")[0].trim().toUpperCase();
    const value = line.slice(colonIdx + 1);
    current[key] = value;
  }

  return events;
}

function toParsedEvent(fields: Record<string, string>): ParsedEvent {
  const uid = fields["UID"];
  const summary = fields["SUMMARY"];
  const dtstart = fields["DTSTART"];
  if (!uid || !summary || !dtstart) {
    throw new Error("Missing required ICS fields (UID/SUMMARY/DTSTART)");
  }

  const name = unescapeIcsText(summary);
  const location = fields["LOCATION"] ? unescapeIcsText(fields["LOCATION"]) : null;
  const { city, country } = splitLocation(location);
  const resolvedCity =
    city ?? (country && /india/i.test(country) ? guessIndiaCityFromName(name) : null);

  return {
    source_uid: uid.trim(),
    name,
    race_date: parseIcsDate(dtstart),
    race_end_date: fields["DTEND"] ? parseIcsDate(fields["DTEND"]) : null,
    location_raw: location,
    city: resolvedCity,
    country,
    distance_label: guessDistanceLabel(name),
    registration_url: fields["URL"] ? unescapeIcsText(fields["URL"]) : null,
    organizer: fields["ORGANIZER"] ? unescapeIcsText(fields["ORGANIZER"]) : null,
  };
}

Deno.serve(async () => {
  try {
    const icsResponse = await fetch(AIMS_FEED_URL);
    if (!icsResponse.ok) {
      throw new Error(`AIMS feed fetch failed: ${icsResponse.status}`);
    }
    const icsText = await icsResponse.text();
    const events = parseEvents(icsText);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const rows = events.map((e) => ({ source: "aims", ...e }));

    const { error } = await supabase
      .from("races")
      .upsert(rows, { onConflict: "source,source_uid" });

    if (error) throw error;

    return new Response(
      JSON.stringify({ ok: true, synced: rows.length }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ ok: false, error: String(err) }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});
