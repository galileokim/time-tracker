import Testing
@testable import TimeTrackerCore

struct AccountValidationTests {
    @Test func acceptsSingleCharacterCredentialsWithProviderEmail() {
        #expect(AccountValidation.registrationProblems(username: "g", email: "g@gmail.com", password: "g").isEmpty)
        #expect(AccountValidation.registrationProblems(username: "galileo", email: "galileo@gmail.com", password: "galileo").isEmpty)
    }

    @Test func reportsEachMissingOrMalformedField() {
        let problems = AccountValidation.registrationProblems(username: " ", email: "@gmail.com", password: "")
        #expect(problems == ["Enter a username.", "Enter an email address like name@gmail.com.", "Enter a password."])
    }

    @Test(arguments: ["g@gmail", "gmail.com", "g @gmail.com", "g@", ""])
    func rejectsEmailsWithoutNameAndProviderDomain(email: String) {
        #expect(!AccountValidation.isValidEmail(email))
    }
}
