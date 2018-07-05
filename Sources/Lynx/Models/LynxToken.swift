//
//  LynxToken.swift
//  App
//
//  Created by Andrei GHERGHE on 06/05/2018.
//
// thanks @bensyverson

import FluentMySQL
import Vapor
import Authentication
import Crypto

final class LynxToken: MySQLUUIDModel {
    var id: UUID?

    var token: String
    var userID: UUID

    init(id: UUID? = nil, string: String, user: User) throws {
        self.id = id
        self.token = string
        guard let loggedUserId = user.id else {
            throw Abort.init(.badRequest)
        }
        self.userID = loggedUserId
    }
}

extension LynxToken {
    var user: Parent<LynxToken, User> {
        return parent(\.userID)
    }
}

extension LynxToken: Migration { }
extension LynxToken: Content { }
extension LynxToken: Parameter { }

extension LynxToken: Token {
    static var userIDKey: WritableKeyPath<LynxToken, UUID> {
        return \LynxToken.userID
    }

    static var tokenKey: WritableKeyPath<LynxToken, String> {
        return \LynxToken.token
    }

    typealias UserType = User
}

extension Request {
    func user() -> User? {
        return try? requireAuthenticated(User.self)
    }
}

extension LynxToken {
    /// Generates a new token for the supplied User.
    static func generate(for user: User) throws -> LynxToken {
        let aToken = try LynxToken.randomToken()
        return try LynxToken(string: aToken, user: user)
    }

    static func randomToken() throws -> String {
        // generate 128 random bits using OpenSSL
        let random = try CryptoRandom().generateData(count: 32)
        // create and return the new token
        return random.base64URLEncodedString()
    }
}

public final class NonThrowingTokenAuthenticationMiddleware<A>: Middleware where A: TokenAuthenticatable {
    /// The underlying bearer auth middleware.
    public let bearer: BearerAuthenticationMiddleware<A.TokenType>

    /// Create a new `TokenAuthenticationMiddleware`
    public init(bearer: BearerAuthenticationMiddleware<A.TokenType>) {
        self.bearer = bearer
    }

    /// See Middleware.respond
    public func respond(to req: Request, chainingTo next: Responder) throws -> Future<Response> {
        let responder = BasicResponder { req in
            guard let token = try? req.requireAuthenticated(A.TokenType.self) else {
                return try next.respond(to: req)
            }
            return A.authenticate(token: token, on: req).flatMap { user in
                if let user = user {
                    try req.authenticate(user)
                }
                return try next.respond(to: req)
            }
        }
        return try bearer.respond(to: req, chainingTo: responder)
    }
}

extension TokenAuthenticatable where Self: Model {
    /// Creates a basic auth middleware for this model.
    /// See `BasicAuthenticationMiddleware`.
    public static func nonThrowingTokenAuthMiddleware(database: DatabaseIdentifier<Database>? = nil) -> NonThrowingTokenAuthenticationMiddleware<Self> {
        return .init(bearer: TokenType.bearerAuthMiddleware())
    }
}
