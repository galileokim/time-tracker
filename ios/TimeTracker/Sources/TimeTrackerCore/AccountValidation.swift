import Foundation

/// Mirrors the backend's signup rules so problems are reported before a request is sent.
public enum AccountValidation {
    public static func registrationProblems(username: String, email: String, password: String) -> [String] {
        var problems: [String] = []
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            problems.append("Enter a username.")
        }
        if !isValidEmail(email) {
            problems.append("Enter an email address like name@gmail.com.")
        }
        if password.isEmpty {
            problems.append("Enter a password.")
        }
        return problems
    }

    /// At least one character before the @ and a provider domain after it, such as name@gmail.com.
    public static func isValidEmail(_ email: String) -> Bool {
        email.trimmingCharacters(in: .whitespacesAndNewlines).wholeMatch(of: /[^\s@]+@[^\s@]+\.[^\s@]+/) != nil
    }
}
