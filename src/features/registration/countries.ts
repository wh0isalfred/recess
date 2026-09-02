/**
 * Country calling codes for the WhatsApp number field.
 *
 * Not exhaustive — every ITU-assigned code exists, but RECESS's actual reach
 * is Nigeria plus the diaspora and a handful of neighbours, and a 195-row
 * dropdown is worse UX than a curated one for every real registrant. Nigeria
 * is first and is the field's default; the rest are alphabetical by country
 * name so a name search (native `<select>` typeahead) works the way people
 * expect.
 *
 * `nsnLength` is the expected national significant number length — digits
 * after the country code, ignoring formatting — used only for a soft
 * "looks short/long" hint. The server's E.164 shape check is authoritative;
 * this is UX, not validation.
 */
export type Country = {
  iso2: string;
  name: string;
  dialCode: string;
  nsnLength: number;
};

export const COUNTRIES: Country[] = [
  { iso2: "NG", name: "Nigeria", dialCode: "234", nsnLength: 10 },
  { iso2: "GH", name: "Ghana", dialCode: "233", nsnLength: 9 },
  { iso2: "KE", name: "Kenya", dialCode: "254", nsnLength: 9 },
  { iso2: "ZA", name: "South Africa", dialCode: "27", nsnLength: 9 },
  { iso2: "EG", name: "Egypt", dialCode: "20", nsnLength: 10 },
  { iso2: "ET", name: "Ethiopia", dialCode: "251", nsnLength: 9 },
  { iso2: "TZ", name: "Tanzania", dialCode: "255", nsnLength: 9 },
  { iso2: "UG", name: "Uganda", dialCode: "256", nsnLength: 9 },
  { iso2: "RW", name: "Rwanda", dialCode: "250", nsnLength: 9 },
  { iso2: "SN", name: "Senegal", dialCode: "221", nsnLength: 9 },
  { iso2: "CI", name: "Côte d'Ivoire", dialCode: "225", nsnLength: 10 },
  { iso2: "CM", name: "Cameroon", dialCode: "237", nsnLength: 9 },
  { iso2: "BJ", name: "Benin", dialCode: "229", nsnLength: 8 },
  { iso2: "TG", name: "Togo", dialCode: "228", nsnLength: 8 },
  { iso2: "MA", name: "Morocco", dialCode: "212", nsnLength: 9 },
  { iso2: "DZ", name: "Algeria", dialCode: "213", nsnLength: 9 },
  { iso2: "TN", name: "Tunisia", dialCode: "216", nsnLength: 8 },
  { iso2: "ZM", name: "Zambia", dialCode: "260", nsnLength: 9 },
  { iso2: "ZW", name: "Zimbabwe", dialCode: "263", nsnLength: 9 },
  { iso2: "AE", name: "United Arab Emirates", dialCode: "971", nsnLength: 9 },
  { iso2: "SA", name: "Saudi Arabia", dialCode: "966", nsnLength: 9 },
  { iso2: "QA", name: "Qatar", dialCode: "974", nsnLength: 8 },
  { iso2: "GB", name: "United Kingdom", dialCode: "44", nsnLength: 10 },
  { iso2: "IE", name: "Ireland", dialCode: "353", nsnLength: 9 },
  { iso2: "US", name: "United States", dialCode: "1", nsnLength: 10 },
  { iso2: "CA", name: "Canada", dialCode: "1", nsnLength: 10 },
  { iso2: "FR", name: "France", dialCode: "33", nsnLength: 9 },
  { iso2: "DE", name: "Germany", dialCode: "49", nsnLength: 10 },
  { iso2: "IN", name: "India", dialCode: "91", nsnLength: 10 },
  { iso2: "CN", name: "China", dialCode: "86", nsnLength: 11 },
  { iso2: "BR", name: "Brazil", dialCode: "55", nsnLength: 11 },
  { iso2: "AU", name: "Australia", dialCode: "61", nsnLength: 9 },
];

export const DEFAULT_COUNTRY_ISO2 = "NG";

export function findCountry(iso2: string): Country {
  return COUNTRIES.find((c) => c.iso2 === iso2) ?? COUNTRIES[0];
}
