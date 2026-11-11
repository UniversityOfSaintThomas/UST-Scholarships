/**
 * Pure helpers for the essay sections of Page 2. Kept free of any LWC imports so they can be unit tested.
 */

// How the applicant chooses to give an essay answer (the "I will enter my answer by:" select in the VF page).
export const DELIVERY_UPLOAD = "upload";
export const DELIVERY_INPUT = "input";

export const DELIVERY_OPTIONS = [
    {label: "Uploading an essay", value: DELIVERY_UPLOAD},
    {label: "Copy and pasting an essay", value: DELIVERY_INPUT}
];

/**
 * True when rich text contains something visible, so editor leftovers such as "<p><br></p>" count as empty.
 */
export function hasText(html) {
    if (!html) {
        return false;
    }
    if (/<img/i.test(html)) {
        return true;
    }
    return html.replace(/<[^>]*>/g, "").replace(/&nbsp;/gi, " ").trim() !== "";
}

/**
 * The option selected when the page opens, as in the VF page: "upload" when a file is already uploaded,
 * "input" when text was already typed, otherwise nothing selected. Essays that cannot be uploaded are
 * always typed.
 */
export function initialDelivery(essay) {
    if (!essay.allowUpload) {
        return DELIVERY_INPUT;
    }
    if (essay.uploaded) {
        return DELIVERY_UPLOAD;
    }
    if (hasText(essay.answerHtml)) {
        return DELIVERY_INPUT;
    }
    return "";
}

/**
 * For example [".pdf", ".doc", ".docx", ".txt", ".rtf"] becomes ".pdf, .doc, .docx, .txt, or .rtf".
 */
export function allowedExtensionsText(extensions) {
    const list = extensions || [];
    if (list.length <= 1) {
        return list.join("");
    }
    if (list.length === 2) {
        return `${list[0]} or ${list[1]}`;
    }
    return `${list.slice(0, -1).join(", ")}, or ${list[list.length - 1]}`;
}
