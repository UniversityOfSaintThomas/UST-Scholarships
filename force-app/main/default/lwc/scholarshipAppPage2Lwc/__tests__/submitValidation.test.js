import {
    EMAIL_MESSAGE,
    errorsFromInvalidFields,
    ESSAY_ANY_MESSAGE,
    ESSAY_CHOICE_MESSAGE,
    ESSAY_TEXT_MESSAGE,
    ESSAY_UPLOAD_MESSAGE,
    REQUIRED_MESSAGE,
    validateForSubmit
} from "../submitValidation";

const complete = () => ({
    questions: [{questionNumber: 1, answer: "An answer"}],
    essays: [{essayNumber: 1, allowUpload: true, delivery: "input", answerHtml: "<p>Essay</p>", uploaded: false}],
    recommenders: [{recommenderNumber: 1, required: true, name: "Dr One", email: "one@example.com"}],
    completionStatementHtml: "<p>I agree</p>",
    signature: "AB"
});

describe("validateForSubmit", () => {
    it("accepts a complete application", () => {
        const result = validateForSubmit(complete());
        expect(result.isValid).toBe(true);
        expect(result.errors).toEqual({});
    });

    it("accepts an application with nothing to fill in", () => {
        expect(validateForSubmit({}).isValid).toBe(true);
        expect(validateForSubmit({questions: [], essays: [], recommenders: []}).isValid).toBe(true);
    });

    describe("questions", () => {
        it.each([
            ["null", null],
            ["empty", ""],
            ["spaces", "   "]
        ])("require an answer, not a %s one", (_label, answer) => {
            const application = complete();
            application.questions = [{questionNumber: 1, answer}, {questionNumber: 3, answer: "Fine"}];

            const result = validateForSubmit(application);

            expect(result.isValid).toBe(false);
            expect(result.errors).toEqual({"question:1": REQUIRED_MESSAGE});
        });

        it("reports every unanswered question", () => {
            const application = complete();
            application.questions = [{questionNumber: 1, answer: ""}, {questionNumber: 2, answer: "ok"}, {questionNumber: 4, answer: null}];

            expect(Object.keys(validateForSubmit(application).errors)).toEqual(["question:1", "question:4"]);
        });
    });

    describe("essays that allow uploads", () => {
        const withEssay = (essay) => ({...complete(), essays: [{essayNumber: 2, allowUpload: true, uploaded: false, answerHtml: null, ...essay}]});

        it("need a choice", () => {
            expect(validateForSubmit(withEssay({delivery: ""})).errors).toEqual({"essay:2": ESSAY_CHOICE_MESSAGE});
            expect(validateForSubmit(withEssay({delivery: undefined})).errors).toEqual({"essay:2": ESSAY_CHOICE_MESSAGE});
        });

        it("need an uploaded file when upload is chosen", () => {
            expect(validateForSubmit(withEssay({delivery: "upload", uploaded: false})).errors).toEqual({"essay:2": ESSAY_UPLOAD_MESSAGE});
            expect(validateForSubmit(withEssay({delivery: "upload", uploaded: true})).isValid).toBe(true);
        });

        it("need text when typing is chosen", () => {
            expect(validateForSubmit(withEssay({delivery: "input", answerHtml: null})).errors).toEqual({"essay:2": ESSAY_TEXT_MESSAGE});
            expect(validateForSubmit(withEssay({delivery: "input", answerHtml: "<p><br></p>"})).errors).toEqual({"essay:2": ESSAY_TEXT_MESSAGE});
            expect(validateForSubmit(withEssay({delivery: "input", answerHtml: "<p>Words</p>"})).isValid).toBe(true);
        });

        it("only look at the chosen option", () => {
            expect(validateForSubmit(withEssay({delivery: "upload", uploaded: false, answerHtml: "<p>Typed earlier</p>"})).isValid).toBe(false);
            expect(validateForSubmit(withEssay({delivery: "input", uploaded: true, answerHtml: null})).isValid).toBe(false);
        });
    });

    it("lets an essay that can only be typed stay empty, as the VF page did", () => {
        const application = complete();
        application.essays = [{essayNumber: 1, allowUpload: false, delivery: "input", answerHtml: null, uploaded: false}];

        expect(validateForSubmit(application).isValid).toBe(true);
    });

    describe("recommenders", () => {
        const withRecommender = (recommender) => ({...complete(), recommenders: [{recommenderNumber: 2, required: true, name: "Dr", email: "dr@example.com", ...recommender}]});

        it("need a name and an email when required", () => {
            expect(validateForSubmit(withRecommender({name: "", email: ""})).errors).toEqual({
                "recommender:2:name": REQUIRED_MESSAGE,
                "recommender:2:email": REQUIRED_MESSAGE
            });
        });

        it("need the email to be valid", () => {
            expect(validateForSubmit(withRecommender({email: "not an email"})).errors).toEqual({"recommender:2:email": EMAIL_MESSAGE});
        });

        it("need a name when only the email is filled in", () => {
            expect(validateForSubmit(withRecommender({name: "  "})).errors).toEqual({"recommender:2:name": REQUIRED_MESSAGE});
        });

        it("may be left empty when optional", () => {
            expect(validateForSubmit(withRecommender({required: false, name: "", email: ""})).isValid).toBe(true);
            expect(validateForSubmit(withRecommender({required: false, name: "Only a name", email: ""})).isValid).toBe(true);
        });

        it("accept a required recommender whose request was already sent", () => {
            expect(validateForSubmit(withRecommender({requestedOn: "May 3, 2026 02:15 PM"})).isValid).toBe(true);
        });
    });

    describe("initials", () => {
        it("are required when there is a completion statement", () => {
            const application = {...complete(), signature: ""};
            expect(validateForSubmit(application).errors).toEqual({signature: REQUIRED_MESSAGE});
            expect(validateForSubmit({...complete(), signature: "   "}).errors).toEqual({signature: REQUIRED_MESSAGE});
            expect(validateForSubmit({...complete(), signature: null}).errors).toEqual({signature: REQUIRED_MESSAGE});
        });

        it("are not required without a completion statement", () => {
            expect(validateForSubmit({...complete(), completionStatementHtml: null, signature: ""}).isValid).toBe(true);
            expect(validateForSubmit({...complete(), completionStatementHtml: "", signature: ""}).isValid).toBe(true);
        });
    });

    it("reports problems in every section at once", () => {
        const result = validateForSubmit({
            questions: [{questionNumber: 1, answer: ""}],
            essays: [{essayNumber: 1, allowUpload: true, delivery: "", uploaded: false, answerHtml: null}],
            recommenders: [{recommenderNumber: 1, required: true, name: "", email: ""}],
            completionStatementHtml: "<p>I agree</p>",
            signature: ""
        });

        expect(result.isValid).toBe(false);
        expect(Object.keys(result.errors)).toEqual(["question:1", "essay:1", "recommender:1:name", "recommender:1:email", "signature"]);
    });
});

describe("errorsFromInvalidFields", () => {
    it("gives each field name returned by the server a message", () => {
        expect(errorsFromInvalidFields([
            "question:1", "essay:2", "recommender:1:name", "recommender:1:email", "signature"
        ])).toEqual({
            "question:1": REQUIRED_MESSAGE,
            "essay:2": ESSAY_ANY_MESSAGE,
            "recommender:1:name": REQUIRED_MESSAGE,
            "recommender:1:email": EMAIL_MESSAGE,
            signature: REQUIRED_MESSAGE
        });
    });

    it("handles no fields", () => {
        expect(errorsFromInvalidFields([])).toEqual({});
        expect(errorsFromInvalidFields(undefined)).toEqual({});
    });
});
