import {createElement} from "lwc";
import ScholarshipHomeLwc from "c/scholarshipHomeLwc";
import {getRecord} from "lightning/uiRecordApi";

// Replace the navigation stub with one that records Navigate calls and returns a fixed URL.
jest.mock("lightning/navigation", () => {
    const Navigate = Symbol("Navigate");
    const GenerateUrl = Symbol("GenerateUrl");
    const mockNavigate = jest.fn();
    const mockGenerateUrl = jest.fn(() => Promise.resolve("/Admissions/s/"));
    const NavigationMixin = (Base) => class extends Base {
        [Navigate](...args) {
            mockNavigate(...args);
        }

        [GenerateUrl](...args) {
            return mockGenerateUrl(...args);
        }
    };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return {NavigationMixin, __mockNavigate: mockNavigate, __mockGenerateUrl: mockGenerateUrl};
}, {virtual: true});

const {__mockNavigate: mockNavigate, __mockGenerateUrl: mockGenerateUrl} = require("lightning/navigation");

// eslint-disable-next-line @lwc/lwc/no-async-operation
const flushPromises = () => new Promise((resolve) => setTimeout(resolve, 0));

const q = (element, selector) => element.shadowRoot.querySelector(selector);

function mount(props = {}) {
    const element = createElement("c-scholarship-home-lwc", {is: ScholarshipHomeLwc});
    Object.assign(element, props);
    document.body.appendChild(element);
    return element;
}

describe("c-scholarship-home-lwc", () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it("shows the Scholarships heading and embeds the eligible scholarship list", async () => {
        const element = mount();
        await flushPromises();

        expect(q(element, '[data-id="heading"]').textContent).toBe("Scholarships");
        expect(q(element, "c-scholarship-eligible-list-view")).not.toBeNull();
    });

    it("shows 'Scholarships for' the user's first and last name", async () => {
        const element = mount();
        getRecord.emit({fields: {FirstName: {value: "Ada"}, LastName: {value: "Lovelace"}}});
        await flushPromises();

        expect(q(element, '[data-id="user-line"]').textContent).toBe("Scholarships for Ada Lovelace");
    });

    it("hides the user line until the name is known", async () => {
        const element = mount();
        await flushPromises();

        expect(q(element, '[data-id="user-line"]')).toBeNull();
    });

    it("uses only the part of the name that exists", async () => {
        const element = mount();
        getRecord.emit({fields: {FirstName: {value: null}, LastName: {value: "Lovelace"}}});
        await flushPromises();

        expect(q(element, '[data-id="user-line"]').textContent).toBe("Scholarships for Lovelace");
    });

    it("builds the Admissions Home link from the configured page", async () => {
        const element = mount({admissionsHomePageName: "Custom_Home__c", admissionsHomeLabel: "Back to Admissions"});
        await flushPromises();

        expect(mockGenerateUrl).toHaveBeenCalledWith({type: "comm__namedPage", attributes: {name: "Custom_Home__c"}});
        const link = q(element, '[data-id="admissions-home"]');
        expect(link.textContent).toBe("Back to Admissions");
        expect(link.getAttribute("href")).toBe("/Admissions/s/");
    });

    it("defaults the Admissions Home link to the standard Home page", async () => {
        const element = mount();
        await flushPromises();

        expect(q(element, '[data-id="admissions-home"]').textContent).toBe("Admissions Home");
        expect(mockGenerateUrl).toHaveBeenCalledWith({type: "comm__namedPage", attributes: {name: "Home"}});
    });

    it("navigates without a full page load when the link is clicked", async () => {
        const element = mount();
        await flushPromises();

        const event = new CustomEvent("click", {cancelable: true});
        q(element, '[data-id="admissions-home"]').dispatchEvent(event);

        expect(event.defaultPrevented).toBe(true);
        expect(mockNavigate).toHaveBeenCalledWith({type: "comm__namedPage", attributes: {name: "Home"}});
    });

    it("keeps working when the link URL cannot be generated", async () => {
        mockGenerateUrl.mockReturnValueOnce(Promise.reject(new Error("no url")));
        const element = mount();
        await flushPromises();

        expect(q(element, '[data-id="admissions-home"]').getAttribute("href")).toBe("#");
    });
});
