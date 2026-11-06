import {createElement} from "lwc";
import ScholarshipClosedLwc from "c/scholarshipClosedLwc";
import {CurrentPageReference} from "lightning/navigation";
import getAccessStatus from "@salesforce/apex/ScholarshipLwcService.getAccessStatus";

jest.mock("@salesforce/apex/ScholarshipLwcService.getAccessStatus", () => ({default: jest.fn()}), {virtual: true});

const SID = "Scholarship-ABC";
const OPEN_DISPLAY = "Monday January 05, 2026 8:00 AM CST";
const CLOSE_DISPLAY = "Friday January 30, 2026 5:00 PM CST";

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

async function mountWith(access, sid = SID) {
    getAccessStatus.mockResolvedValue(access);
    const element = createElement("c-scholarship-closed-lwc", {is: ScholarshipClosedLwc});
    document.body.appendChild(element);
    CurrentPageReference.emit({state: sid ? {sid} : {}});
    await flushPromises();
    return element;
}

const q = (element, selector) => element.shadowRoot.querySelector(selector);

describe("c-scholarship-closed-lwc", () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it("asks Apex about the sid in the URL and shows the scholarship name", async () => {
        const element = await mountWith({status: "CLOSED", scholarshipName: "Test Scholarship", displayCloseDateTime: CLOSE_DISPLAY});

        expect(getAccessStatus).toHaveBeenCalledWith({sid: SID});
        expect(q(element, '[data-id="name"]').textContent).toBe("Test Scholarship");
    });

    it("explains when the scholarship has already closed", async () => {
        const element = await mountWith({
            status: "CLOSED",
            scholarshipName: "Test Scholarship",
            displayOpenDateTime: OPEN_DISPLAY,
            displayCloseDateTime: CLOSE_DISPLAY
        });

        expect(q(element, '[data-id="message"]').textContent).toBe(
            `We're sorry. The Test Scholarship closed on ${CLOSE_DISPLAY}. Thank you for your interest.`
        );
    });

    it("explains when the scholarship has not opened yet", async () => {
        const element = await mountWith({
            status: "NOT_YET_OPEN",
            scholarshipName: "Test Scholarship",
            displayOpenDateTime: OPEN_DISPLAY,
            displayCloseDateTime: CLOSE_DISPLAY
        });

        expect(q(element, '[data-id="message"]').textContent).toBe(
            `We're sorry. The Test Scholarship has not opened yet. It will open on ${OPEN_DISPLAY}. ` +
            "Please return after the open date and fill out your application then. Thank you for your interest!"
        );
    });

    it.each([
        ["OPEN"],
        ["COMPLETE"]
    ])("shows the generic closed message when the status is %s", async (status) => {
        const element = await mountWith({
            status,
            scholarshipName: "Test Scholarship",
            displayOpenDateTime: OPEN_DISPLAY,
            displayCloseDateTime: CLOSE_DISPLAY
        });

        expect(q(element, '[data-id="message"]').textContent).toBe(
            "We're sorry. The Test Scholarship is currently closed. Thank you for your interest!"
        );
    });

    it("falls back to the generic message when the closing date is missing", async () => {
        const element = await mountWith({status: "CLOSED", scholarshipName: "Test Scholarship"});

        expect(q(element, '[data-id="message"]').textContent).toBe(
            "We're sorry. The Test Scholarship is currently closed. Thank you for your interest!"
        );
    });

    it("shows a generic message without a name when the scholarship is not found", async () => {
        const element = await mountWith({status: "NOT_FOUND"});

        expect(q(element, '[data-id="name"]')).toBeNull();
        expect(q(element, '[data-id="message"]').textContent).toBe(
            "We're sorry. This scholarship is currently closed. Thank you for your interest!"
        );
    });

    it("shows the generic message without calling Apex when the URL has no sid", async () => {
        const element = await mountWith({status: "CLOSED"}, null);

        expect(getAccessStatus).not.toHaveBeenCalled();
        expect(q(element, '[data-id="message"]').textContent).toBe(
            "We're sorry. This scholarship is currently closed. Thank you for your interest!"
        );
    });

    it("shows an error when loading fails", async () => {
        getAccessStatus.mockRejectedValue({body: {message: "Boom"}});
        const element = createElement("c-scholarship-closed-lwc", {is: ScholarshipClosedLwc});
        document.body.appendChild(element);
        CurrentPageReference.emit({state: {sid: SID}});
        await flushPromises();

        expect(q(element, '[data-id="error-message"]').textContent).toContain("Boom");
        expect(q(element, '[data-id="message"]')).toBeNull();
    });
});
