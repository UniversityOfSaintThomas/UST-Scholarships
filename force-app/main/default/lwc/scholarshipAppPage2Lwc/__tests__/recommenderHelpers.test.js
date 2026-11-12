import {canRequestRecommendation, isValidEmail} from "../recommenderHelpers";

describe("isValidEmail", () => {
    it.each([
        "person@example.com",
        "first.last@example.com",
        "first.last+tag@sub.example.org",
        " padded@example.com "
    ])("accepts %s", (email) => {
        expect(isValidEmail(email)).toBe(true);
    });

    it.each([
        ["blank", ""],
        ["spaces only", "   "],
        ["no at sign", "no-at-sign.example.com"],
        ["two at signs", "two@@example.com"],
        ["spaces inside", "spaces in@example.com"],
        ["no dot in the domain", "missing-dot@example"],
        ["nothing before the at sign", "@example.com"],
        ["nothing after the at sign", "person@"]
    ])("rejects an address with %s", (_label, email) => {
        expect(isValidEmail(email)).toBe(false);
    });

    it("rejects values that are not text", () => {
        expect(isValidEmail(null)).toBe(false);
        expect(isValidEmail(undefined)).toBe(false);
        expect(isValidEmail(42)).toBe(false);
    });
});

describe("canRequestRecommendation", () => {
    it("needs both a name and a valid email", () => {
        expect(canRequestRecommendation("Dr One", "one@example.com")).toBe(true);
        expect(canRequestRecommendation("", "one@example.com")).toBe(false);
        expect(canRequestRecommendation("   ", "one@example.com")).toBe(false);
        expect(canRequestRecommendation("Dr One", "")).toBe(false);
        expect(canRequestRecommendation("Dr One", "not an email")).toBe(false);
        expect(canRequestRecommendation(null, null)).toBe(false);
        expect(canRequestRecommendation(undefined, undefined)).toBe(false);
    });
});
