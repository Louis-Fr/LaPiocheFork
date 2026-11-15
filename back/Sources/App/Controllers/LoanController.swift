import Fluent
import Vapor

struct LoanController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let loans = routes.grouped("loans")
        loans.get(use: index)
        loans.post(use: create)
        loans.post(":id", "return", use: returnLoan)
    }
    
    @Sendable
    func index(req: Request) async throws -> [LoanDTO] {
        let loans = try await Loan.query(on: req.db)
            .all()
        return loans.map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        let dto = try req.content.decode(CreateLoanDTO.self)

        guard let game = try await Game.find(dto.gameID, on: req.db) else {
            throw Abort(.notFound, reason: "Game not found")
        }
        guard let member = try await Member.find(dto.memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        
        try await ensureGameIsAvailable(game, on: req.db)

        let now = Date()
        let loan = Loan(
            gameID: try game.requireID(),
            memberID: try member.requireID(),
            borrowedAt: now,
            dueAt: try Loan.dueDate(from: now)
        )
        try await loan.save(on: req.db)
        return try await loan.toDTO().encodeResponse(status: .created, for: req)
    }
    
    @Sendable
    func ensureGameIsAvailable(_ game: Game, on db: any Database) async throws {
        let isOnLoan = try await Loan.query(on: db)
            .filter(\.$returnedAt == nil)
            .count() > 0
        
        if isOnLoan {
            throw Abort(.conflict, reason: "Game is already on loan")
        }
    }
    
    @Sendable
    func returnLoan(req: Request) async throws -> LoanDTO {
        guard let loan = try await Loan.find(req.parameters.get("id"), on: req.db) else {
            throw Abort(.notFound, reason: "Loan not found")
        }
        
        guard loan.returnedAt == nil else {
            throw Abort(.conflict, reason: "Loan already returned")
        }
        
        loan.returnedAt = Date()
        try await loan.save(on: req.db)
        return loan.toDTO()
    }
}
