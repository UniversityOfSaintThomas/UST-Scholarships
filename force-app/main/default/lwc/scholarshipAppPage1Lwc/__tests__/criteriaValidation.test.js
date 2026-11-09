import {
    ACT_SAT_ERROR,
    CONFIRM_ERROR,
    GPA_ERROR,
    parseNumber,
    validateCriteria
} from "../criteriaValidation";

const valid = {confirmed: true, selfReportRequired: true, gpa: "3.5", actSat: "27"};

describe("validateCriteria", () => {
    it("accepts a confirmed form with valid self reported values", () => {
        const result = validateCriteria(valid);
        expect(result.isValid).toBe(true);
        expect(result.errors).toEqual({gpa: null, actSat: null, confirmed: null});
    });

    it("requires the confirmation checkbox", () => {
        const result = validateCriteria({...valid, confirmed: false});
        expect(result.isValid).toBe(false);
        expect(result.errors.confirmed).toBe(CONFIRM_ERROR);
        expect(result.errors.gpa).toBeNull();
    });

    it("only requires the checkbox when self reporting is off", () => {
        expect(validateCriteria({confirmed: true, selfReportRequired: false, gpa: "", actSat: ""}).isValid).toBe(true);
        expect(validateCriteria({confirmed: false, selfReportRequired: false, gpa: "", actSat: ""}).isValid).toBe(false);
    });

    it.each([
        ["blank", ""],
        ["null", null],
        ["non numeric", "abc"],
        ["below the minimum", "0.99"],
        ["above the field maximum", "10"]
    ])("rejects a %s GPA", (_label, gpa) => {
        const result = validateCriteria({...valid, gpa});
        expect(result.isValid).toBe(false);
        expect(result.errors.gpa).toBe(GPA_ERROR);
        expect(result.errors.actSat).toBeNull();
    });

    it("accepts the GPA lower bound", () => {
        expect(validateCriteria({...valid, gpa: "1.0"}).isValid).toBe(true);
        expect(validateCriteria({...valid, gpa: 1}).isValid).toBe(true);
    });

    it.each([
        ["blank", ""],
        ["null", null],
        ["non numeric", "abc"],
        ["below the minimum", "9"],
        ["a decimal", "27.5"],
        ["above the field maximum", "10000"]
    ])("rejects a %s ACT/SAT score", (_label, actSat) => {
        const result = validateCriteria({...valid, actSat});
        expect(result.isValid).toBe(false);
        expect(result.errors.actSat).toBe(ACT_SAT_ERROR);
        expect(result.errors.gpa).toBeNull();
    });

    it("accepts the ACT/SAT lower bound", () => {
        expect(validateCriteria({...valid, actSat: "10"}).isValid).toBe(true);
    });

    it("reports every error at once", () => {
        const result = validateCriteria({confirmed: false, selfReportRequired: true, gpa: "", actSat: ""});
        expect(result.errors).toEqual({gpa: GPA_ERROR, actSat: ACT_SAT_ERROR, confirmed: CONFIRM_ERROR});
    });
});

describe("parseNumber", () => {
    it("returns null for blank or invalid values and a number otherwise", () => {
        expect(parseNumber("")).toBeNull();
        expect(parseNumber(null)).toBeNull();
        expect(parseNumber(undefined)).toBeNull();
        expect(parseNumber("abc")).toBeNull();
        expect(parseNumber("3.5")).toBe(3.5);
        expect(parseNumber(27)).toBe(27);
    });
});
