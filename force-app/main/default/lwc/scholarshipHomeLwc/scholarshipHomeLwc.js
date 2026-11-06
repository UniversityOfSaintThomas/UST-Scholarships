import {api, LightningElement, wire} from "lwc";
import {NavigationMixin} from "lightning/navigation";
import {getRecord} from "lightning/uiRecordApi";
import USER_ID from "@salesforce/user/Id";
import FIRST_NAME from "@salesforce/schema/User.FirstName";
import LAST_NAME from "@salesforce/schema/User.LastName";

/**
 * LWC replacement for the ScholarshipHome VF page chrome: the "Scholarships" heading, the
 * "Scholarships for {first name} {last name}" line and the "Admissions Home" link, followed by the
 * eligible scholarship list. The list itself is the existing scholarshipEligibleListView component.
 */
export default class ScholarshipHomeLwc extends NavigationMixin(LightningElement) {

    // Experience Builder page the "Admissions Home" link opens. "Home" is the site's standard home page.
    @api admissionsHomePageName = "Home";
    @api admissionsHomeLabel = "Admissions Home";

    admissionsHomeUrl = "#";
    firstName;
    lastName;

    @wire(getRecord, {recordId: USER_ID, fields: [FIRST_NAME, LAST_NAME]})
    wiredUser({data}) {
        if (data) {
            this.firstName = data.fields.FirstName ? data.fields.FirstName.value : undefined;
            this.lastName = data.fields.LastName ? data.fields.LastName.value : undefined;
        }
    }

    get fullName() {
        return [this.firstName, this.lastName].filter(Boolean).join(" ");
    }

    connectedCallback() {
        this[NavigationMixin.GenerateUrl](this.admissionsHomePageReference)
            .then((url) => {
                this.admissionsHomeUrl = url;
            })
            .catch(() => {
                // Keep the "#" fallback; the click handler still navigates.
            });
    }

    get admissionsHomePageReference() {
        return {
            type: "comm__namedPage",
            attributes: {name: this.admissionsHomePageName}
        };
    }

    handleAdmissionsHomeClick(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate](this.admissionsHomePageReference);
    }
}
