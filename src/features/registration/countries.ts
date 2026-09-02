/**
 * Country calling codes for the WhatsApp number field.
 *
 * The full ITU-assigned list — every UN member plus the common territories —
 * not a curated subset. RECESS's own reach starts in Nigeria, which is why
 * it leads the list and is the field's default, but the person filling this
 * in may be registering from anywhere, and the field should not assume
 * otherwise. The rest is alphabetical by country name so a name search
 * (native `<select>` typeahead) works the way people expect.
 *
 * `nsnLength` is the expected national significant number length — digits
 * after the country code, ignoring formatting — used only for a soft
 * "looks short/long" hint. The server's E.164 shape check is authoritative;
 * this is UX, not validation. Where a country's length genuinely varies
 * (some do), this holds the most common length and the soft-range check in
 * validation.ts already tolerates a couple of digits either side.
 */
export type Country = {
  iso2: string;
  name: string;
  dialCode: string;
  nsnLength: number;
};

export const COUNTRIES: Country[] = [
  { iso2: "NG", name: "Nigeria", dialCode: "234", nsnLength: 10 },

  { iso2: "AF", name: "Afghanistan", dialCode: "93", nsnLength: 9 },
  { iso2: "AL", name: "Albania", dialCode: "355", nsnLength: 9 },
  { iso2: "DZ", name: "Algeria", dialCode: "213", nsnLength: 9 },
  { iso2: "AS", name: "American Samoa", dialCode: "1684", nsnLength: 7 },
  { iso2: "AD", name: "Andorra", dialCode: "376", nsnLength: 6 },
  { iso2: "AO", name: "Angola", dialCode: "244", nsnLength: 9 },
  { iso2: "AI", name: "Anguilla", dialCode: "1264", nsnLength: 7 },
  { iso2: "AG", name: "Antigua and Barbuda", dialCode: "1268", nsnLength: 7 },
  { iso2: "AR", name: "Argentina", dialCode: "54", nsnLength: 10 },
  { iso2: "AM", name: "Armenia", dialCode: "374", nsnLength: 8 },
  { iso2: "AW", name: "Aruba", dialCode: "297", nsnLength: 7 },
  { iso2: "AU", name: "Australia", dialCode: "61", nsnLength: 9 },
  { iso2: "AT", name: "Austria", dialCode: "43", nsnLength: 10 },
  { iso2: "AZ", name: "Azerbaijan", dialCode: "994", nsnLength: 9 },

  { iso2: "BS", name: "Bahamas", dialCode: "1242", nsnLength: 7 },
  { iso2: "BH", name: "Bahrain", dialCode: "973", nsnLength: 8 },
  { iso2: "BD", name: "Bangladesh", dialCode: "880", nsnLength: 10 },
  { iso2: "BB", name: "Barbados", dialCode: "1246", nsnLength: 7 },
  { iso2: "BY", name: "Belarus", dialCode: "375", nsnLength: 9 },
  { iso2: "BE", name: "Belgium", dialCode: "32", nsnLength: 9 },
  { iso2: "BZ", name: "Belize", dialCode: "501", nsnLength: 7 },
  { iso2: "BJ", name: "Benin", dialCode: "229", nsnLength: 8 },
  { iso2: "BM", name: "Bermuda", dialCode: "1441", nsnLength: 7 },
  { iso2: "BT", name: "Bhutan", dialCode: "975", nsnLength: 8 },
  { iso2: "BO", name: "Bolivia", dialCode: "591", nsnLength: 8 },
  { iso2: "BA", name: "Bosnia and Herzegovina", dialCode: "387", nsnLength: 8 },
  { iso2: "BW", name: "Botswana", dialCode: "267", nsnLength: 8 },
  { iso2: "BR", name: "Brazil", dialCode: "55", nsnLength: 11 },
  { iso2: "IO", name: "British Indian Ocean Territory", dialCode: "246", nsnLength: 7 },
  { iso2: "VG", name: "British Virgin Islands", dialCode: "1284", nsnLength: 7 },
  { iso2: "BN", name: "Brunei", dialCode: "673", nsnLength: 7 },
  { iso2: "BG", name: "Bulgaria", dialCode: "359", nsnLength: 9 },
  { iso2: "BF", name: "Burkina Faso", dialCode: "226", nsnLength: 8 },
  { iso2: "BI", name: "Burundi", dialCode: "257", nsnLength: 8 },

  { iso2: "KH", name: "Cambodia", dialCode: "855", nsnLength: 9 },
  { iso2: "CM", name: "Cameroon", dialCode: "237", nsnLength: 9 },
  { iso2: "CA", name: "Canada", dialCode: "1", nsnLength: 10 },
  { iso2: "CV", name: "Cape Verde", dialCode: "238", nsnLength: 7 },
  { iso2: "KY", name: "Cayman Islands", dialCode: "1345", nsnLength: 7 },
  { iso2: "CF", name: "Central African Republic", dialCode: "236", nsnLength: 8 },
  { iso2: "TD", name: "Chad", dialCode: "235", nsnLength: 8 },
  { iso2: "CL", name: "Chile", dialCode: "56", nsnLength: 9 },
  { iso2: "CN", name: "China", dialCode: "86", nsnLength: 11 },
  { iso2: "CO", name: "Colombia", dialCode: "57", nsnLength: 10 },
  { iso2: "KM", name: "Comoros", dialCode: "269", nsnLength: 7 },
  { iso2: "CG", name: "Congo-Brazzaville", dialCode: "242", nsnLength: 9 },
  { iso2: "CD", name: "Congo-Kinshasa (DRC)", dialCode: "243", nsnLength: 9 },
  { iso2: "CK", name: "Cook Islands", dialCode: "682", nsnLength: 5 },
  { iso2: "CR", name: "Costa Rica", dialCode: "506", nsnLength: 8 },
  { iso2: "CI", name: "Côte d'Ivoire", dialCode: "225", nsnLength: 10 },
  { iso2: "HR", name: "Croatia", dialCode: "385", nsnLength: 9 },
  { iso2: "CU", name: "Cuba", dialCode: "53", nsnLength: 8 },
  { iso2: "CW", name: "Curaçao", dialCode: "599", nsnLength: 7 },
  { iso2: "CY", name: "Cyprus", dialCode: "357", nsnLength: 8 },
  { iso2: "CZ", name: "Czechia", dialCode: "420", nsnLength: 9 },

  { iso2: "DK", name: "Denmark", dialCode: "45", nsnLength: 8 },
  { iso2: "DJ", name: "Djibouti", dialCode: "253", nsnLength: 6 },
  { iso2: "DM", name: "Dominica", dialCode: "1767", nsnLength: 7 },
  { iso2: "DO", name: "Dominican Republic", dialCode: "1", nsnLength: 10 },

  { iso2: "EC", name: "Ecuador", dialCode: "593", nsnLength: 9 },
  { iso2: "EG", name: "Egypt", dialCode: "20", nsnLength: 10 },
  { iso2: "SV", name: "El Salvador", dialCode: "503", nsnLength: 8 },
  { iso2: "GQ", name: "Equatorial Guinea", dialCode: "240", nsnLength: 9 },
  { iso2: "ER", name: "Eritrea", dialCode: "291", nsnLength: 7 },
  { iso2: "EE", name: "Estonia", dialCode: "372", nsnLength: 8 },
  { iso2: "SZ", name: "Eswatini", dialCode: "268", nsnLength: 8 },
  { iso2: "ET", name: "Ethiopia", dialCode: "251", nsnLength: 9 },

  { iso2: "FK", name: "Falkland Islands", dialCode: "500", nsnLength: 5 },
  { iso2: "FO", name: "Faroe Islands", dialCode: "298", nsnLength: 6 },
  { iso2: "FJ", name: "Fiji", dialCode: "679", nsnLength: 7 },
  { iso2: "FI", name: "Finland", dialCode: "358", nsnLength: 9 },
  { iso2: "FR", name: "France", dialCode: "33", nsnLength: 9 },
  { iso2: "GF", name: "French Guiana", dialCode: "594", nsnLength: 9 },
  { iso2: "PF", name: "French Polynesia", dialCode: "689", nsnLength: 8 },

  { iso2: "GA", name: "Gabon", dialCode: "241", nsnLength: 8 },
  { iso2: "GM", name: "Gambia", dialCode: "220", nsnLength: 7 },
  { iso2: "GE", name: "Georgia", dialCode: "995", nsnLength: 9 },
  { iso2: "DE", name: "Germany", dialCode: "49", nsnLength: 10 },
  { iso2: "GH", name: "Ghana", dialCode: "233", nsnLength: 9 },
  { iso2: "GI", name: "Gibraltar", dialCode: "350", nsnLength: 8 },
  { iso2: "GR", name: "Greece", dialCode: "30", nsnLength: 10 },
  { iso2: "GL", name: "Greenland", dialCode: "299", nsnLength: 6 },
  { iso2: "GD", name: "Grenada", dialCode: "1473", nsnLength: 7 },
  { iso2: "GP", name: "Guadeloupe", dialCode: "590", nsnLength: 9 },
  { iso2: "GU", name: "Guam", dialCode: "1671", nsnLength: 7 },
  { iso2: "GT", name: "Guatemala", dialCode: "502", nsnLength: 8 },
  { iso2: "GN", name: "Guinea", dialCode: "224", nsnLength: 9 },
  { iso2: "GW", name: "Guinea-Bissau", dialCode: "245", nsnLength: 7 },
  { iso2: "GY", name: "Guyana", dialCode: "592", nsnLength: 7 },

  { iso2: "HT", name: "Haiti", dialCode: "509", nsnLength: 8 },
  { iso2: "HN", name: "Honduras", dialCode: "504", nsnLength: 8 },
  { iso2: "HK", name: "Hong Kong", dialCode: "852", nsnLength: 8 },
  { iso2: "HU", name: "Hungary", dialCode: "36", nsnLength: 9 },

  { iso2: "IS", name: "Iceland", dialCode: "354", nsnLength: 7 },
  { iso2: "IN", name: "India", dialCode: "91", nsnLength: 10 },
  { iso2: "ID", name: "Indonesia", dialCode: "62", nsnLength: 11 },
  { iso2: "IR", name: "Iran", dialCode: "98", nsnLength: 10 },
  { iso2: "IQ", name: "Iraq", dialCode: "964", nsnLength: 10 },
  { iso2: "IE", name: "Ireland", dialCode: "353", nsnLength: 9 },
  { iso2: "IL", name: "Israel", dialCode: "972", nsnLength: 9 },
  { iso2: "IT", name: "Italy", dialCode: "39", nsnLength: 10 },

  { iso2: "JM", name: "Jamaica", dialCode: "1876", nsnLength: 7 },
  { iso2: "JP", name: "Japan", dialCode: "81", nsnLength: 10 },
  { iso2: "JO", name: "Jordan", dialCode: "962", nsnLength: 9 },

  { iso2: "KZ", name: "Kazakhstan", dialCode: "7", nsnLength: 10 },
  { iso2: "KE", name: "Kenya", dialCode: "254", nsnLength: 9 },
  { iso2: "KI", name: "Kiribati", dialCode: "686", nsnLength: 5 },
  { iso2: "XK", name: "Kosovo", dialCode: "383", nsnLength: 8 },
  { iso2: "KW", name: "Kuwait", dialCode: "965", nsnLength: 8 },
  { iso2: "KG", name: "Kyrgyzstan", dialCode: "996", nsnLength: 9 },

  { iso2: "LA", name: "Laos", dialCode: "856", nsnLength: 9 },
  { iso2: "LV", name: "Latvia", dialCode: "371", nsnLength: 8 },
  { iso2: "LB", name: "Lebanon", dialCode: "961", nsnLength: 8 },
  { iso2: "LS", name: "Lesotho", dialCode: "266", nsnLength: 8 },
  { iso2: "LR", name: "Liberia", dialCode: "231", nsnLength: 8 },
  { iso2: "LY", name: "Libya", dialCode: "218", nsnLength: 9 },
  { iso2: "LI", name: "Liechtenstein", dialCode: "423", nsnLength: 7 },
  { iso2: "LT", name: "Lithuania", dialCode: "370", nsnLength: 8 },
  { iso2: "LU", name: "Luxembourg", dialCode: "352", nsnLength: 9 },

  { iso2: "MO", name: "Macau", dialCode: "853", nsnLength: 8 },
  { iso2: "MG", name: "Madagascar", dialCode: "261", nsnLength: 9 },
  { iso2: "MW", name: "Malawi", dialCode: "265", nsnLength: 9 },
  { iso2: "MY", name: "Malaysia", dialCode: "60", nsnLength: 9 },
  { iso2: "MV", name: "Maldives", dialCode: "960", nsnLength: 7 },
  { iso2: "ML", name: "Mali", dialCode: "223", nsnLength: 8 },
  { iso2: "MT", name: "Malta", dialCode: "356", nsnLength: 8 },
  { iso2: "MH", name: "Marshall Islands", dialCode: "692", nsnLength: 7 },
  { iso2: "MQ", name: "Martinique", dialCode: "596", nsnLength: 9 },
  { iso2: "MR", name: "Mauritania", dialCode: "222", nsnLength: 8 },
  { iso2: "MU", name: "Mauritius", dialCode: "230", nsnLength: 8 },
  { iso2: "MX", name: "Mexico", dialCode: "52", nsnLength: 10 },
  { iso2: "FM", name: "Micronesia", dialCode: "691", nsnLength: 7 },
  { iso2: "MD", name: "Moldova", dialCode: "373", nsnLength: 8 },
  { iso2: "MC", name: "Monaco", dialCode: "377", nsnLength: 8 },
  { iso2: "MN", name: "Mongolia", dialCode: "976", nsnLength: 8 },
  { iso2: "ME", name: "Montenegro", dialCode: "382", nsnLength: 8 },
  { iso2: "MS", name: "Montserrat", dialCode: "1664", nsnLength: 7 },
  { iso2: "MA", name: "Morocco", dialCode: "212", nsnLength: 9 },
  { iso2: "MZ", name: "Mozambique", dialCode: "258", nsnLength: 9 },
  { iso2: "MM", name: "Myanmar", dialCode: "95", nsnLength: 9 },

  { iso2: "NA", name: "Namibia", dialCode: "264", nsnLength: 9 },
  { iso2: "NR", name: "Nauru", dialCode: "674", nsnLength: 7 },
  { iso2: "NP", name: "Nepal", dialCode: "977", nsnLength: 10 },
  { iso2: "NL", name: "Netherlands", dialCode: "31", nsnLength: 9 },
  { iso2: "NC", name: "New Caledonia", dialCode: "687", nsnLength: 6 },
  { iso2: "NZ", name: "New Zealand", dialCode: "64", nsnLength: 9 },
  { iso2: "NI", name: "Nicaragua", dialCode: "505", nsnLength: 8 },
  { iso2: "NE", name: "Niger", dialCode: "227", nsnLength: 8 },
  { iso2: "NU", name: "Niue", dialCode: "683", nsnLength: 4 },
  { iso2: "MK", name: "North Macedonia", dialCode: "389", nsnLength: 8 },
  { iso2: "NO", name: "Norway", dialCode: "47", nsnLength: 8 },

  { iso2: "OM", name: "Oman", dialCode: "968", nsnLength: 8 },

  { iso2: "PK", name: "Pakistan", dialCode: "92", nsnLength: 10 },
  { iso2: "PW", name: "Palau", dialCode: "680", nsnLength: 7 },
  { iso2: "PS", name: "Palestine", dialCode: "970", nsnLength: 9 },
  { iso2: "PA", name: "Panama", dialCode: "507", nsnLength: 8 },
  { iso2: "PG", name: "Papua New Guinea", dialCode: "675", nsnLength: 8 },
  { iso2: "PY", name: "Paraguay", dialCode: "595", nsnLength: 9 },
  { iso2: "PE", name: "Peru", dialCode: "51", nsnLength: 9 },
  { iso2: "PH", name: "Philippines", dialCode: "63", nsnLength: 10 },
  { iso2: "PL", name: "Poland", dialCode: "48", nsnLength: 9 },
  { iso2: "PT", name: "Portugal", dialCode: "351", nsnLength: 9 },
  { iso2: "PR", name: "Puerto Rico", dialCode: "1", nsnLength: 10 },

  { iso2: "QA", name: "Qatar", dialCode: "974", nsnLength: 8 },

  { iso2: "RE", name: "Réunion", dialCode: "262", nsnLength: 9 },
  { iso2: "RO", name: "Romania", dialCode: "40", nsnLength: 9 },
  { iso2: "RU", name: "Russia", dialCode: "7", nsnLength: 10 },
  { iso2: "RW", name: "Rwanda", dialCode: "250", nsnLength: 9 },

  { iso2: "WS", name: "Samoa", dialCode: "685", nsnLength: 7 },
  { iso2: "SM", name: "San Marino", dialCode: "378", nsnLength: 10 },
  { iso2: "ST", name: "São Tomé and Príncipe", dialCode: "239", nsnLength: 7 },
  { iso2: "SA", name: "Saudi Arabia", dialCode: "966", nsnLength: 9 },
  { iso2: "SN", name: "Senegal", dialCode: "221", nsnLength: 9 },
  { iso2: "RS", name: "Serbia", dialCode: "381", nsnLength: 9 },
  { iso2: "SC", name: "Seychelles", dialCode: "248", nsnLength: 7 },
  { iso2: "SL", name: "Sierra Leone", dialCode: "232", nsnLength: 8 },
  { iso2: "SG", name: "Singapore", dialCode: "65", nsnLength: 8 },
  { iso2: "SK", name: "Slovakia", dialCode: "421", nsnLength: 9 },
  { iso2: "SI", name: "Slovenia", dialCode: "386", nsnLength: 8 },
  { iso2: "SB", name: "Solomon Islands", dialCode: "677", nsnLength: 7 },
  { iso2: "SO", name: "Somalia", dialCode: "252", nsnLength: 8 },
  { iso2: "ZA", name: "South Africa", dialCode: "27", nsnLength: 9 },
  { iso2: "KR", name: "South Korea", dialCode: "82", nsnLength: 10 },
  { iso2: "SS", name: "South Sudan", dialCode: "211", nsnLength: 9 },
  { iso2: "ES", name: "Spain", dialCode: "34", nsnLength: 9 },
  { iso2: "LK", name: "Sri Lanka", dialCode: "94", nsnLength: 9 },
  { iso2: "SD", name: "Sudan", dialCode: "249", nsnLength: 9 },
  { iso2: "SR", name: "Suriname", dialCode: "597", nsnLength: 7 },
  { iso2: "SE", name: "Sweden", dialCode: "46", nsnLength: 9 },
  { iso2: "CH", name: "Switzerland", dialCode: "41", nsnLength: 9 },
  { iso2: "SY", name: "Syria", dialCode: "963", nsnLength: 9 },

  { iso2: "TW", name: "Taiwan", dialCode: "886", nsnLength: 9 },
  { iso2: "TJ", name: "Tajikistan", dialCode: "992", nsnLength: 9 },
  { iso2: "TZ", name: "Tanzania", dialCode: "255", nsnLength: 9 },
  { iso2: "TH", name: "Thailand", dialCode: "66", nsnLength: 9 },
  { iso2: "TL", name: "Timor-Leste", dialCode: "670", nsnLength: 8 },
  { iso2: "TG", name: "Togo", dialCode: "228", nsnLength: 8 },
  { iso2: "TO", name: "Tonga", dialCode: "676", nsnLength: 7 },
  { iso2: "TT", name: "Trinidad and Tobago", dialCode: "1868", nsnLength: 7 },
  { iso2: "TN", name: "Tunisia", dialCode: "216", nsnLength: 8 },
  { iso2: "TR", name: "Turkey", dialCode: "90", nsnLength: 10 },
  { iso2: "TM", name: "Turkmenistan", dialCode: "993", nsnLength: 8 },
  { iso2: "TC", name: "Turks and Caicos Islands", dialCode: "1649", nsnLength: 7 },
  { iso2: "TV", name: "Tuvalu", dialCode: "688", nsnLength: 5 },

  { iso2: "UG", name: "Uganda", dialCode: "256", nsnLength: 9 },
  { iso2: "UA", name: "Ukraine", dialCode: "380", nsnLength: 9 },
  { iso2: "AE", name: "United Arab Emirates", dialCode: "971", nsnLength: 9 },
  { iso2: "GB", name: "United Kingdom", dialCode: "44", nsnLength: 10 },
  { iso2: "US", name: "United States", dialCode: "1", nsnLength: 10 },
  { iso2: "UY", name: "Uruguay", dialCode: "598", nsnLength: 8 },
  { iso2: "UZ", name: "Uzbekistan", dialCode: "998", nsnLength: 9 },

  { iso2: "VU", name: "Vanuatu", dialCode: "678", nsnLength: 7 },
  { iso2: "VA", name: "Vatican City", dialCode: "39", nsnLength: 10 },
  { iso2: "VE", name: "Venezuela", dialCode: "58", nsnLength: 10 },
  { iso2: "VN", name: "Vietnam", dialCode: "84", nsnLength: 9 },
  { iso2: "VI", name: "Virgin Islands (U.S.)", dialCode: "1340", nsnLength: 7 },

  { iso2: "YE", name: "Yemen", dialCode: "967", nsnLength: 9 },

  { iso2: "ZM", name: "Zambia", dialCode: "260", nsnLength: 9 },
  { iso2: "ZW", name: "Zimbabwe", dialCode: "263", nsnLength: 9 },
];

export const DEFAULT_COUNTRY_ISO2 = "NG";

export function findCountry(iso2: string): Country {
  return COUNTRIES.find((c) => c.iso2 === iso2) ?? COUNTRIES[0];
}
