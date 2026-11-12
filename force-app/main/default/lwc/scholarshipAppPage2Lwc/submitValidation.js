import {DELIVERY_INPUT, DELIVERY_UPLOAD, hasText} from "./essayHelpers";
import {isValidEmail} from "./recommenderHelpers";

/**
 * The completeness rules for Save & Submit, checked in the browser before anything is sent. They follow
 * validateApplication() in the VF page's script, and ScholarshipAppPage2LwcController.validateForSubmit() applies
 * the same rules on the server, which is the authoritative check. Kept free of any LWC imports so it can be unit
 * tested.
 *
 * Errors are returned as an object keyed the same way the server names fields:
 * "question:1", "essay:1", "recommender:1:name", "recommender:1:email" and "signature".
 */

export const REQUIRED_MESSAGE = "This field is required.";
export const EMAIL_MESSAGE = "Please enter a valid email address.";
export const ESSAY_CHOICE_MESSAGE = "Please choose how you will enter your answer.";
export const ESSAY_UPLOAD_MESSAGE = "Please upload your essay file.";
export const ESSAY_TEXT_MESSAGE = "Please enter your essay.";
export const ESSAY_ANY_MESSAGE = "Please upload your essay file or enter your essay.";

function isBlank(value) {
    return value === null || value === undefined || String(value).trim() === "";
}

/**
 * @param {{questions: Array, essays: Array, recommenders: Array, completionStatementHtml: string, signature: string}} application
 *        What the applicant has on the page. Essays carry the option they chose ("delivery").
 * @returns {{isValid: boolean, errors: Object<string, string>}} The first problem found for each field.
 */
export function validateForSubmit({questions, essays, recommenders, completionStatementHtml, signature}) {
    const errors = {};

    // Every configured question needs an answer.
    (questions || []).forEach((question) => {
        if (isBlank(question.answer)) {
            errors[`question:${question.questionNumber}`] = REQUIRED_MESSAGE;
        }
    });

    // Like the VF page, only an essay that allows uploads must be answered. The applicant picks one option, and
    // that option is what has to be filled in. An essay that can only be typed may be left empty.
    (essays || []).forEach((essay) => {
        if (!essay.allowUpload) {
            return;
        }
        const key = `essay:${essay.essayNumber}`;
        if (essay.delivery === DELIVERY_UPLOAD) {
            if (!essay.uploaded) {
                errors[key] = ESSAY_UPLOAD_MESSAGE;
            }
        } else if (essay.delivery === DELIVERY_INPUT) {
            if (!hasText(essay.answerHtml)) {
                errors[key] = ESSAY_TEXT_MESSAGE;
            }
        } else {
            errors[key] = ESSAY_CHOICE_MESSAGE;
        }
    });

    // A recommender marked "Required" needs a name and a valid email. Optional ones may be left empty.
    (recommenders || []).forEach((recommender) => {
        if (!recommender.required) {
            return;
        }
        if (isBlank(recommender.name)) {
            errors[`recommender:${recommender.recommenderNumber}:name`] = REQUIRED_MESSAGE;
        }
        if (!isValidEmail(recommender.email)) {
            errors[`recommender:${recommender.recommenderNumber}:email`] = isBlank(recommender.email) ? REQUIRED_MESSAGE : EMAIL_MESSAGE;
        }
    });

    // The initials are only asked for when the scholarship has a completion statement.
    if (!isBlank(completionStatementHtml) && isBlank(signature)) {
        errors.signature = REQUIRED_MESSAGE;
    }

    return {isValid: Object.keys(errors).length === 0, errors};
}

/**
 * Turns the field names the server returns for an incomplete application into messages for the page.
 *
 * @param {string[]} invalidFields Field names such as "question:1" or "recommender:1:email".
 * @returns {Object<string, string>} The same keys with a message each.
 */
export function errorsFromInvalidFields(invalidFields) {
    const errors = {};
    (invalidFields || []).forEach((field) => {
        if (field.startsWith("essay:")) {
            errors[field] = ESSAY_ANY_MESSAGE;
        } else if (field.endsWith(":email")) {
            errors[field] = EMAIL_MESSAGE;
        } else {
            errors[field] = REQUIRED_MESSAGE;
        }
    });
    return errors;
}
