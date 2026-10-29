import Testing
@testable import BibliaCore

private func p(_ s: String) throws -> BibleRef { try ReferenceParser.parse(s) }

@Suite struct ReferenceParserTests {
    @Test func examples() throws {
        #expect(try p("Juan 3:16-18") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 18))
        #expect(try p("Jn 3") == BibleRef(book: 43, chapter: 3, verseFrom: nil, verseTo: nil))
        #expect(try p("约3:16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(try p("约翰福音 3:16").book == 43)
        #expect(try p("2 Tim 3:16") == BibleRef(book: 55, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(try p("提后3:16").book == 55)
        #expect(try p("Romans 8:28") == BibleRef(book: 45, chapter: 8, verseFrom: 28, verseTo: 28))
        #expect(try p("Apocalipsis 1:1").book == 66)
        #expect(try p("Rev 22:21") == BibleRef(book: 66, chapter: 22, verseFrom: 21, verseTo: 21))
        #expect(try p("创1:1") == BibleRef(book: 1, chapter: 1, verseFrom: 1, verseTo: 1))
        #expect(try p("Salmos 23") == BibleRef(book: 19, chapter: 23, verseFrom: nil, verseTo: nil))
        #expect(try p("约3：16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
    }

    @Test func accentsCaseNumericAndPrefix() throws {
        #expect(try p("GÉNESIS 1:1").book == 1)
        #expect(try p("genesis 1").book == 1)
        #expect(try p("Jeremias 1").book == 24)
        #expect(try p("43 3:16").book == 43)
        #expect(try p("Deut 6:4").book == 5)
        #expect(try p("Apocal 1:1").book == 66)
        #expect(try p("1 Cor 13").book == 46)
        #expect(try p("Juan 3:16–18").verseTo == 18)
    }

    @Test(arguments: ["", "Juan", "Juan 3:", "Foo 3:16", "xyz", "67 1:1", "3:16", "J 3"])
    func invalid(_ bad: String) {
        #expect(throws: (any Error).self) { try ReferenceParser.parse(bad) }
    }

    @Test func bookTable() throws {
        #expect(ReferenceParser.books.count == 66)
        for b in ReferenceParser.books { #expect(try ReferenceParser.resolveBook(b.2) == b.0) }
    }

    @Test func traditionalNamesAreAccepted() throws {
        #expect(try ReferenceParser.parse("約3:16") == BibleRef(book: 43, chapter: 3, verseFrom: 16, verseTo: 16))
        #expect(try ReferenceParser.parse("約翰福音 3:16").book == 43)
        #expect(try ReferenceParser.parse("創1:1") == BibleRef(book: 1, chapter: 1, verseFrom: 1, verseTo: 1))
        #expect(try ReferenceParser.parse("啟示錄 22").book == 66)
        #expect(try ReferenceParser.parse("詩篇 23").book == 19)
        #expect(try ReferenceParser.parse("約壹 4:8").book == 62)
        #expect(try ReferenceParser.parse("约3:16").book == 43)
        for (i, t) in ReferenceParser.traditional.enumerated() {
            #expect(try ReferenceParser.resolveBook(t.0) == i + 1, "\(t.0)")
            #expect(try ReferenceParser.resolveBook(t.1) == i + 1, "\(t.1)")
        }
    }
}
