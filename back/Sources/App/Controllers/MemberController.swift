import Fluent
import Vapor

struct MemberController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let members = routes.grouped("members")
        members.get(use: index)
        members.post(use: create)
        members.get(":memberID", use: show)
        members.put(":memberID", use: modify)
        members.delete(":memberID", use: delete)
        members.get(":memberID", "loans", use: showLoans)
    }

    @Sendable
    func index(req: Request) async throws -> [MemberDTO] {
        try await Member.query(on: req.db).all().map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateMemberDTO.validate(content: req)
        let dto = try req.content.decode(CreateMemberDTO.self)

        let emailTaken = try await Member.query(on: req.db)
            .filter(\.$email == dto.email)
            .count() > 0
        guard !emailTaken else {
            throw Abort(.conflict, reason: "A member with this email already exists")
        }

        let member = dto.toModel()
        try await member.save(on: req.db)
        return try await member.toDTO().encodeResponse(status: .created, for: req)
    }

    @Sendable
    func show(req: Request) async throws -> MemberDTO {
        guard let memberID = req.parameters.get("memberID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid member id")
        }
        guard let member = try await Member.find(memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        return member.toDTO()
    }
    
    private func findMember(_ req: Request) async throws -> Member {
        guard let memberID = req.parameters.get("memberID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid member id")
        }
        guard let member = try await Member.find(memberID, on: req.db) else {
            throw Abort(.notFound, reason: "Member not found")
        }
        return member
    }
    
    
    @Sendable
    func modify(req: Request) async throws -> MemberDTO {
        let member = try await findMember(req)
        
        try CreateMemberDTO.validate(content: req)
        let dto = try req.content.decode(CreateMemberDTO.self)
        
        let verifyEmail = try await Member.query(on: req.db)
            .filter(\.$email == dto.email)
            .filter(\.$id != member.requireID())
            .count() > 0
        guard !verifyEmail else {
            throw Abort(.conflict, reason: "A member with this email already exists")
        }
        
        member.email = dto.email
        member.name = dto.name
        
        try await member.update(on: req.db)
        return member.toDTO()
    }
    
    @Sendable
    func delete(req: Request) async throws -> HTTPResponseStatus {
        let member = try await findMember(req)   // 400 (id invalide) / 404 (introuvable)
        try await member.$loans.load(on: req.db)

        guard member.loans.isEmpty else {
            throw Abort(.conflict, reason: "Member has loans and cannot be deleted")
        }

        try await member.delete(on: req.db)
        return .noContent
    }
    
    @Sendable
    func showLoans(req: Request) async throws -> [LoanDTO] {
        let member = try await findMember(req)
        return try await member.$loans.query(on: req.db).all().map { $0.toDTO() }
    }
    
}
