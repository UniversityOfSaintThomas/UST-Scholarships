/**
 * Pure helpers for the recommender sections of Page 2. Kept free of any LWC imports so they can be unit tested.
 */

// The email pattern from isValidEmailAddress() in the scholarships static resource (scripts.js), used by the
// VF page. The VF page only ever checked that the email was not empty (a typo stopped this check running).
// eslint-disable-next-line no-control-regex, no-useless-escape
const EMAIL_PATTERN = /^([a-z\d!#$%&'*+\-\/=?^_`{|}~\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]+(\.[a-z\d!#$%&'*+\-\/=?^_`{|}~\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]+)*|"((([ \t]*\r\n)?[ \t]+)?([\x01-\x08\x0b\x0c\x0e-\x1f\x7f\x21\x23-\x5b\x5d-\x7e\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]|\\[\x01-\x09\x0b\x0c\x0d-\x7f\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]))*(([ \t]*\r\n)?[ \t]+)?")@(([a-z\d\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]|[a-z\d\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF][a-z\d\-._~\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]*[a-z\d\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])\.)+([a-z\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]|[a-z\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF][a-z\d\-._~\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF]*[a-z\u00A0-\uD7FF\uF900-\uFDCF\uFDF0-\uFFEF])\.?$/i;

/**
 * @param {string} email The address to check.
 * @returns {boolean} True when the address looks like a valid email address.
 */
export function isValidEmail(email) {
    return typeof email === "string" && EMAIL_PATTERN.test(email.trim());
}

/**
 * The rule for enabling "Request Now": a name is filled in and the email address is valid.
 *
 * @param {string} name The recommender's name.
 * @param {string} email The recommender's email address.
 * @returns {boolean} True when a request can be sent.
 */
export function canRequestRecommendation(name, email) {
    return typeof name === "string" && name.trim() !== "" && isValidEmail(email);
}