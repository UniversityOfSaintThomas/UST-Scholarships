import {countWords} from "../wordCount";

describe("countWords", () => {
    it("returns 0 for empty, blank or missing text", () => {
        expect(countWords("")).toBe(0);
        expect(countWords("   ")).toBe(0);
        expect(countWords("\n\t ")).toBe(0);
        expect(countWords(null)).toBe(0);
        expect(countWords(undefined)).toBe(0);
    });

    it("counts words separated by single spaces", () => {
        expect(countWords("one")).toBe(1);
        expect(countWords("one two three")).toBe(3);
    });

    it("treats any run of whitespace as one separator", () => {
        expect(countWords("one   two")).toBe(2);
        expect(countWords("one\ntwo\r\nthree\tfour")).toBe(4);
    });

    it("ignores leading and trailing whitespace", () => {
        expect(countWords("  one two  ")).toBe(2);
        expect(countWords("\none two\n")).toBe(2);
    });
});
