import Combine
import Foundation

@MainActor
final class RemoteAuthenticationSession: ObservableObject {
    enum State: Equatable {
        case signedOut
        case checking
        case signedIn(RemoteAccount)
        case failed(String)
    }

    @Published private(set) var state: State = .checking

    var account: RemoteAccount? {
        guard case .signedIn(let account) = state else { return nil }
        return account
    }

    func refresh() async {
        state = .checking
        do {
            guard let account = try await RemoteTeXCompilerFactory
                .currentAccount() else {
                state = .signedOut
                return
            }
            state = .signedIn(account)
        } catch let error as CompilationError {
            if case .authenticationRequired = error {
                state = .signedOut
            } else {
                state = .failed(error.localizedDescription)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func login(
        serverURL: String,
        email: String,
        password: String
    ) async throws {
        state = .checking
        do {
            let account = try await RemoteTeXCompilerFactory.login(
                serverURL: serverURL,
                email: email,
                password: password
            )
            state = .signedIn(account)
        } catch {
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    func logout() {
        RemoteTeXCompilerFactory.logout()
        state = .signedOut
    }
}
