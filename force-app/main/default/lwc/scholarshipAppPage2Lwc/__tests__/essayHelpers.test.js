import {
    allowedExtensionsText,
    DELIVERY_INPUT,
    DELIVERY_OPTIONS,
    DELIVERY_UPLOAD,
    hasText,
    initialDelivery
} from "../essayHelpers";

describe("hasText", () => {
    it("is false for empty text and editor leftovers", () => {
        expect(hasText(null)).toBe(false);
        expect(hasText(undefined)).toBe(false);
        expect(hasText("")).toBe(false);
        expect(hasText("   ")).toBe(false);
        expect(hasText("<p><br></p>")).toBe(false);
        expect(hasText("<p>&nbsp;</p>")).toBe(false);
        expect(hasText("<p> </p><p>&nbsp;</p>")).toBe(false);
    });

    it("is true when there is visible text", () => {
        expect(hasText("<p>Hello</p>")).toBe(true);
        expect(hasText("plain text")).toBe(true);
        expect(hasText("<p><strong>x</strong></p>")).toBe(true);
    });

    it("is true for an image even without text", () => {
        expect(hasText('<p><img src="https://example.com/a.png"></p>')).toBe(true);
    });
});

describe("initialDelivery", () => {
    it("is always typing when the essay cannot be uploaded", () => {
        expect(initialDelivery({allowUpload: false})).toBe(DELIVERY_INPUT);
        expect(initialDelivery({allowUpload: false, uploaded: true})).toBe(DELIVERY_INPUT);
    });

    it("selects upload when a file was already uploaded, even if text exists too", () => {
        expect(initialDelivery({allowUpload: true, uploaded: true, answerHtml: "<p>text</p>"})).toBe(DELIVERY_UPLOAD);
    });

    it("selects typing when only text exists", () => {
        expect(initialDelivery({allowUpload: true, uploaded: false, answerHtml: "<p>text</p>"})).toBe(DELIVERY_INPUT);
    });

    it("selects nothing when there is no file and no text", () => {
        expect(initialDelivery({allowUpload: true, uploaded: false, answerHtml: null})).toBe("");
        expect(initialDelivery({allowUpload: true, uploaded: false, answerHtml: "<p><br></p>"})).toBe("");
    });
});

describe("allowedExtensionsText", () => {
    it("lists extensions the way the VF page worded them", () => {
        expect(allowedExtensionsText([".pdf", ".doc", ".docx", ".txt", ".rtf"])).toBe(".pdf, .doc, .docx, .txt, or .rtf");
    });

    it("handles short or missing lists", () => {
        expect(allowedExtensionsText([".pdf"])).toBe(".pdf");
        expect(allowedExtensionsText([".pdf", ".doc"])).toBe(".pdf or .doc");
        expect(allowedExtensionsText([])).toBe("");
        expect(allowedExtensionsText(undefined)).toBe("");
    });
});

describe("DELIVERY_OPTIONS", () => {
    it("offers the two VF choices", () => {
        expect(DELIVERY_OPTIONS).toEqual([
            {label: "Uploading an essay", value: "upload"},
            {label: "Copy and pasting an essay", value: "input"}
        ]);
    });
});
