public enum Fizz {
    /// Tested, and simple. CRAP should come out at its complexity.
    public static func label(_ number: Int) -> String {
        if number % 15 == 0 {
            return "FizzBuzz"
        }
        return "\(number)"
    }

    /// Untested, and full of branches. This is what the tool exists to find.
    public static func summarize(_ numbers: [Int], verbose: Bool, limit: Int?) -> String {
        var parts: [String] = []
        for number in numbers where number > 0 {
            if number % 3 == 0 && number % 5 == 0 {
                parts.append(verbose ? "FizzBuzz(\(number))" : "FizzBuzz")
            } else if number % 3 == 0 {
                parts.append("Fizz")
            } else if number % 5 == 0 {
                parts.append("Buzz")
            } else {
                parts.append("\(number)")
            }
            if parts.count >= (limit ?? Int.max) {
                break
            }
        }
        return parts.isEmpty ? "empty" : parts.joined(separator: ", ")
    }
}
