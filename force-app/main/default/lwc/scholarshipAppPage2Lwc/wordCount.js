/**
 * Counts the words in a text by splitting on any whitespace (spaces, tabs and line breaks), ignoring
 * leading and trailing whitespace. Kept free of any LWC imports so it can be unit tested.
 */
export function countWords(text) {
    if (text === null || text === undefined) {
        return 0;
    }
    const trimmed = String(text).trim();
    return trimmed === "" ? 0 : trimmed.split(/\s+/).length;
}
