import {createElement} from "lwc";
import ScholarshipRecommenderLwc from "c/scholarshipRecommenderLwc";
import {CurrentPageReference} from "lightning/navigation";
import getRecommendationRequest from "@salesforce/apex/ScholarshipRecommenderLwcController.getRecommendationRequest";
import submitRecommendation from "@salesforce/apex/ScholarshipRecommenderLwcController.submitRecommendation";

jest.mock("@salesforce/apex/ScholarshipRecommenderLwcController.getRecommendationRequest", () => ({default: jest.fn()}), {virtual: true});
jest.mock("@salesforce/apex/ScholarshipRecommenderLwcController.submitRecommendation", () => ({default: jest.fn()}), {virtual: true});

const REC_ID = "a1Ehs000000EHgyEAG1";

const readyData = (overrides = {}) => ({
    status: "READY",
    scholarshipName: "Test Scholarship",
    applicantName: "Ada Student",
    recommenderName: "Dr One",
    scholarshipDescriptionHtml: "<p>Scholarship description</p>",
    questionHtml: "<p>The question</p>",
    recommendationHtml: null,
    ...overrides
});

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mountWith(data, state = {recId: REC_ID}) {
    getRecommendationRequest.mockResolvedValue(data);
    const element = createElement("c-scholarship-recommender-lwc", {is: ScholarshipRecommenderLwc});
    document.body.appendChild(element);
    CurrentPageReference.emit({state});
    await flushPromises();
    return element;
}

const q = (element, selector) => element.shadowRoot.querySelector(selector);
const qAll = (element, selector) => Array.from(element.shadowRoot.querySelectorAll(selector));

function typeRecommendation(element, value) {
    q(element, 'lightning-input-rich-text[data-id="recommendation"]').dispatchEvent(new CustomEvent("change", {detail: {value}}));
}

async function clickSubmit(element) {
    q(element, 'lightning-button[data-id="submit"]').click();
    await flushPromises();
}

describe("c-scholarship-recommender-lwc", () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    describe("opening the link", () => {
        it("asks Apex about the recId in the URL, and nothing else", async () => {
            await mountWith(readyData());

            expect(getRecommendationRequest).toHaveBeenCalledWith({recId: REC_ID});
        });

        it.each([
            ["recId"],
            ["recid"],
            ["RECID"],
            ["RecId"]
        ])("accepts the parameter spelled %s", async (name) => {
            await mountWith(readyData(), {[name]: REC_ID});

            expect(getRecommendationRequest).toHaveBeenCalledWith({recId: REC_ID});
        });

        it("shows the scholarship, the greeting and who asked", async () => {
            const element = await mountWith(readyData());

            expect(q(element, '[data-id="heading"]').textContent).toBe("Test Scholarship");
            expect(q(element, '[data-id="greeting"]').textContent).toBe("Greetings Dr One,");
            expect(q(element, '[data-id="request-text"]').textContent).toBe(
                "You have been requested by Ada Student to provide a recommendation towards the Test Scholarship."
            );
        });

        it("shows the scholarship description and the recommender's question", async () => {
            const element = await mountWith(readyData());

            expect(q(element, '[data-id="description-heading"]').textContent).toBe("Scholarship Description");
            expect(q(element, '[data-id="question-heading"]').textContent).toBe("Your Question");
            const texts = qAll(element, "lightning-formatted-rich-text").map((field) => field.value);
            expect(texts).toEqual(["<p>Scholarship description</p>", "<p>The question</p>"]);
        });

        it("skips the description and the question when there are none", async () => {
            const element = await mountWith(readyData({scholarshipDescriptionHtml: null, questionHtml: null}));

            expect(q(element, '[data-id="description-heading"]')).toBeNull();
            expect(q(element, '[data-id="question-heading"]')).toBeNull();
            expect(q(element, 'lightning-input-rich-text[data-id="recommendation"]')).not.toBeNull();
        });

        it("fills in text that was already stored", async () => {
            const element = await mountWith(readyData({recommendationHtml: "<p>Draft</p>"}));

            expect(q(element, 'lightning-input-rich-text[data-id="recommendation"]').value).toBe("<p>Draft</p>");
        });

        it("shows an error when loading fails", async () => {
            getRecommendationRequest.mockRejectedValue({body: {message: "Boom"}});
            const element = createElement("c-scholarship-recommender-lwc", {is: ScholarshipRecommenderLwc});
            document.body.appendChild(element);
            CurrentPageReference.emit({state: {recId: REC_ID}});
            await flushPromises();

            expect(q(element, '[data-id="load-error"]').textContent).toContain("Boom");
        });
    });

    describe("a link that does not work", () => {
        it("shows only a general message, with no names", async () => {
            const element = await mountWith({status: "INVALID_LINK"});

            expect(q(element, '[data-id="invalid-link"]').textContent).toContain("Could not find this recommendation request");
            expect(q(element, '[data-id="request"]')).toBeNull();
            expect(q(element, '[data-id="submitted"]')).toBeNull();
        });

        it("shows a message instead of calling Apex when there is no link in the URL", async () => {
            const element = await mountWith(readyData(), {});

            expect(getRecommendationRequest).not.toHaveBeenCalled();
            expect(q(element, '[data-id="missing-rec-id"]')).not.toBeNull();
            expect(q(element, '[data-id="request"]')).toBeNull();
        });
    });

    describe("a recommendation that was already submitted", () => {
        it("shows the thank-you message instead of the form", async () => {
            const element = await mountWith(readyData({status: "RECEIVED", recommendationHtml: "<p>Done</p>"}));

            expect(q(element, '[data-id="thank-you"]').textContent).toBe("Thank you for submitting your recommendation for Ada Student.");
            expect(q(element, '[data-id="heading"]').textContent).toBe("Test Scholarship");
            expect(q(element, '[data-id="request"]')).toBeNull();
            expect(q(element, 'lightning-button[data-id="submit"]')).toBeNull();
            expect(q(element, 'lightning-input-rich-text[data-id="recommendation"]')).toBeNull();
        });
    });

    describe("submitting", () => {
        it("sends the link and the text, then shows the thank-you message", async () => {
            submitRecommendation.mockResolvedValue({success: true, status: "RECEIVED"});
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>An excellent student.</p>");
            await flushPromises();

            await clickSubmit(element);

            expect(submitRecommendation).toHaveBeenCalledWith({recId: REC_ID, recommendationHtml: "<p>An excellent student.</p>"});
            expect(q(element, '[data-id="thank-you"]').textContent).toBe("Thank you for submitting your recommendation for Ada Student.");
            expect(q(element, '[data-id="request"]')).toBeNull();
        });

        it.each([
            ["nothing", ""],
            ["only spaces", "   "],
            ["an empty editor", "<p><br></p>"],
            ["a blank paragraph", "<p>&nbsp;</p>"]
        ])("does not call the server for %s", async (_label, value) => {
            const element = await mountWith(readyData());
            typeRecommendation(element, value);
            await flushPromises();

            await clickSubmit(element);

            expect(submitRecommendation).not.toHaveBeenCalled();
            expect(q(element, '[data-id="recommendation-error"]').textContent).toBe("Please enter your recommendation.");
            expect(q(element, '[data-id="thank-you"]')).toBeNull();
        });

        it("clears the error once the recommender types", async () => {
            const element = await mountWith(readyData());
            await clickSubmit(element);
            expect(q(element, '[data-id="recommendation-error"]')).not.toBeNull();

            typeRecommendation(element, "<p>Now there is text</p>");
            await flushPromises();

            expect(q(element, '[data-id="recommendation-error"]')).toBeNull();
        });

        it("accepts a recommendation that is only an image", async () => {
            submitRecommendation.mockResolvedValue({success: true, status: "RECEIVED"});
            const element = await mountWith(readyData());
            typeRecommendation(element, '<p><img src="https://example.com/letter.png"></p>');
            await flushPromises();

            await clickSubmit(element);

            expect(submitRecommendation).toHaveBeenCalledTimes(1);
        });

        it("shows the server's message and keeps the form when the text is rejected", async () => {
            submitRecommendation.mockResolvedValue({success: false, status: "READY", message: "Your recommendation is too long (maximum 32768 characters)."});
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>Very long</p>");
            await flushPromises();

            await clickSubmit(element);

            expect(q(element, '[data-id="submit-error"]').textContent).toContain("too long");
            expect(q(element, '[data-id="request"]')).not.toBeNull();
            expect(q(element, '[data-id="thank-you"]')).toBeNull();
            expect(q(element, 'lightning-button[data-id="submit"]').disabled).toBeFalsy();
        });

        it("keeps what was typed when the save fails", async () => {
            submitRecommendation.mockResolvedValue({success: false, status: "READY", message: "Could not save"});
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>My letter</p>");
            await flushPromises();

            await clickSubmit(element);

            expect(q(element, 'lightning-input-rich-text[data-id="recommendation"]').value).toBe("<p>My letter</p>");
        });

        it("shows the thank-you message when the server says it was already submitted", async () => {
            submitRecommendation.mockResolvedValue({success: false, status: "RECEIVED", message: "A recommendation has already been submitted for this request."});
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>Second try</p>");
            await flushPromises();

            await clickSubmit(element);

            expect(q(element, '[data-id="thank-you"]')).not.toBeNull();
            expect(q(element, '[data-id="request"]')).toBeNull();
        });

        it("shows the general message when the server no longer accepts the link", async () => {
            submitRecommendation.mockResolvedValue({success: false, status: "INVALID_LINK", message: "This recommendation request could not be found."});
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>Text</p>");
            await flushPromises();

            await clickSubmit(element);

            expect(q(element, '[data-id="invalid-link"]')).not.toBeNull();
            expect(q(element, '[data-id="request"]')).toBeNull();
        });

        it("shows an error, and lets the recommender try again, when the Apex call throws", async () => {
            submitRecommendation.mockRejectedValue({body: {message: "Server exploded"}});
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>Text</p>");
            await flushPromises();

            await clickSubmit(element);

            expect(q(element, '[data-id="submit-error"]').textContent).toContain("Server exploded");
            expect(q(element, 'lightning-button[data-id="submit"]').disabled).toBeFalsy();
            expect(q(element, '[data-id="request"]')).not.toBeNull();
        });

        it("cannot be submitted twice while it is being saved", async () => {
            let finish;
            submitRecommendation.mockReturnValue(new Promise((resolve) => {
                finish = resolve;
            }));
            const element = await mountWith(readyData());
            typeRecommendation(element, "<p>Text</p>");
            await flushPromises();

            q(element, 'lightning-button[data-id="submit"]').click();
            await flushPromises();
            expect(q(element, 'lightning-button[data-id="submit"]').disabled).toBe(true);
            q(element, 'lightning-button[data-id="submit"]').click();
            await flushPromises();

            finish({success: true, status: "RECEIVED"});
            await flushPromises();
            expect(submitRecommendation).toHaveBeenCalledTimes(1);
        });
    });
});
