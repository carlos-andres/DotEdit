import Foundation
import Testing
@testable import DotEdit

@Suite("NamingConvention")
struct NamingConventionTests {

    // MARK: - Classification

    @Test("Classifies SCREAMING_SNAKE keys")
    func classifyScreamingSnake() {
        #expect(NamingConvention.classify(key: "DB_HOST") == .screamingSnake)
        #expect(NamingConvention.classify(key: "AWS_SECRET_KEY") == .screamingSnake)
        #expect(NamingConvention.classify(key: "API") == .screamingSnake) // all uppercase, no delimiter
    }

    @Test("Classifies snake_case keys")
    func classifySnakeCase() {
        #expect(NamingConvention.classify(key: "db_host") == .snakeCase)
        #expect(NamingConvention.classify(key: "aws_secret_key") == .snakeCase)
        #expect(NamingConvention.classify(key: "port") == .snakeCase) // all lowercase, no delimiter
    }

    @Test("Classifies dot.notation keys")
    func classifyDotNotation() {
        #expect(NamingConvention.classify(key: "app.url") == .dotNotation)
        #expect(NamingConvention.classify(key: "spring.datasource.url") == .dotNotation)
    }

    @Test("Classifies kebab-case keys")
    func classifyKebabCase() {
        #expect(NamingConvention.classify(key: "db-host") == .kebabCase)
        #expect(NamingConvention.classify(key: "api-base-url") == .kebabCase)
    }

    @Test("Classifies camelCase keys")
    func classifyCamelCase() {
        #expect(NamingConvention.classify(key: "dbHost") == .camelCase)
        #expect(NamingConvention.classify(key: "apiBaseUrl") == .camelCase)
    }

    @Test("Classifies PascalCase keys")
    func classifyPascalCase() {
        #expect(NamingConvention.classify(key: "DbHost") == .pascalCase)
        #expect(NamingConvention.classify(key: "ApiBaseUrl") == .pascalCase)
    }

    @Test("Mixed case with underscores favors convention by ratio")
    func classifyMixedCaseUnderscore() {
        // Mostly uppercase → SCREAMING_SNAKE
        #expect(NamingConvention.classify(key: "DB_Host") == .screamingSnake)
        // Mostly lowercase → snake_case
        #expect(NamingConvention.classify(key: "db_Host") == .snakeCase)
    }

    // MARK: - Dominant Detection

    @Test("Detects dominant convention with high confidence")
    func detectDominantHighConfidence() {
        let keys = ["DB_HOST", "DB_PORT", "DB_NAME", "API_KEY", "API_SECRET",
                     "AWS_REGION", "AWS_BUCKET", "REDIS_URL", "CACHE_TTL", "LOG_LEVEL"]
        let result = NamingConvention.detectDominant(keys: keys)

        #expect(result.dominant == .screamingSnake)
        #expect(result.confidence == 1.0)
        #expect(result.totalKeys == 10)
        #expect(!result.isLowConfidence)
        #expect(!result.isMixed)
    }

    @Test("Detects mixed conventions")
    func detectMixedConventions() {
        let keys = ["DB_HOST", "DB_PORT", "DB_NAME", "app.url", "app.name"]
        let result = NamingConvention.detectDominant(keys: keys)

        #expect(result.dominant == .screamingSnake)
        #expect(result.confidence == 0.6)
        #expect(result.isMixed)
        #expect(result.totalKeys == 5)
    }

    @Test("Empty keys returns default")
    func detectEmptyKeys() {
        let result = NamingConvention.detectDominant(keys: [])
        #expect(result.dominant == .screamingSnake)
        #expect(result.confidence == 0)
        #expect(result.totalKeys == 0)
    }

    @Test("Low confidence with few keys")
    func detectLowConfidence() {
        let keys = ["DB_HOST", "API_KEY"]
        let result = NamingConvention.detectDominant(keys: keys)
        #expect(result.isLowConfidence) // < 5
    }

    // MARK: - Prefix Extraction

    @Test("Extracts SCREAMING_SNAKE prefix")
    func prefixScreamingSnake() {
        #expect(NamingConvention.extractPrefix(key: "DB_HOST", convention: .screamingSnake) == "DB")
        #expect(NamingConvention.extractPrefix(key: "AWS_SECRET_KEY", convention: .screamingSnake) == "AWS")
        #expect(NamingConvention.extractPrefix(key: "PORT", convention: .screamingSnake) == "PORT") // no delimiter
    }

    @Test("Extracts snake_case prefix")
    func prefixSnakeCase() {
        #expect(NamingConvention.extractPrefix(key: "db_host", convention: .snakeCase) == "db")
        #expect(NamingConvention.extractPrefix(key: "api_base_url", convention: .snakeCase) == "api")
    }

    @Test("Extracts dot.notation prefix")
    func prefixDotNotation() {
        #expect(NamingConvention.extractPrefix(key: "app.url", convention: .dotNotation) == "app")
        #expect(NamingConvention.extractPrefix(key: "spring.datasource.url", convention: .dotNotation) == "spring")
    }

    @Test("Extracts kebab-case prefix")
    func prefixKebabCase() {
        #expect(NamingConvention.extractPrefix(key: "db-host", convention: .kebabCase) == "db")
        #expect(NamingConvention.extractPrefix(key: "api-base-url", convention: .kebabCase) == "api")
    }

    @Test("Extracts camelCase prefix")
    func prefixCamelCase() {
        #expect(NamingConvention.extractPrefix(key: "dbHost", convention: .camelCase) == "db")
        #expect(NamingConvention.extractPrefix(key: "apiBaseUrl", convention: .camelCase) == "api")
    }

    @Test("Extracts PascalCase prefix")
    func prefixPascalCase() {
        #expect(NamingConvention.extractPrefix(key: "DbHost", convention: .pascalCase) == "Db")
        #expect(NamingConvention.extractPrefix(key: "ApiBaseUrl", convention: .pascalCase) == "Api")
    }

    @Test("Single-word keys return full key as prefix")
    func prefixSingleWord() {
        #expect(NamingConvention.extractPrefix(key: "PORT", convention: .screamingSnake) == "PORT")
        #expect(NamingConvention.extractPrefix(key: "url", convention: .dotNotation) == "url")
    }
}
