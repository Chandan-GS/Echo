package com.chandangs.echo

/**
 * The second check on "waiting on you": does a message ask anything of the
 * owner? The same tables and the same order of checks as wait_intent.dart,
 * and both run test/fixtures/wait_intent_vectors.tsv. Change them together.
 * No Android imports, so it can run on a plain JVM.
 */
object WaitingIntent {
    enum class Kind {
        question, request, call, invite, deadline, mention, ack, closer, emojiOnly, code, unsure,
    }

    data class Result(val kind: Kind, val needsReply: Boolean)

    val callPhrases = listOf(
        "call me",
        "call back",
        "call when",
        "call asap",
        "call now",
        "call urgent",
        "please call",
        "give me a call",
        "give a call",
        "ring me",
        "phone me",
        "missed call",
        "missed voice call",
        "missed video call",
        "call karo",
        "call kar",
        "call kardo",
        "call karna",
        "phone karo",
        "phone kar",
        "phone kardo",
        "कॉल करो",
        "कॉल कर",
        "कॉल करना",
        "फोन करो",
        "फोन कर",
    )

    val callStarts = setOf(
        "call",
        "ring",
    )

    val requestPhrases = listOf(
        "can you",
        "could you",
        "would you",
        "will you",
        "can u",
        "could u",
        "would u",
        "will u",
        "please",
        "pls",
        "plz",
        "plss",
        "kindly",
        "let me know",
        "lmk",
        "need you to",
        "i need you",
        "want you to",
        "send me",
        "send it",
        "send the",
        "share the",
        "share it",
        "tell me",
        "give me",
        "help me",
        "remind me",
        "take a look",
        "have a look",
        "your thoughts",
        "thoughts on",
        "bhej dena",
        "bhej do",
        "bhej de",
        "bhejo",
        "bhejna",
        "bhejdo",
        "bhej dijiye",
        "kar do",
        "kar dena",
        "kar de",
        "kardo",
        "karde",
        "kar dijiye",
        "karo",
        "batana",
        "bata dena",
        "bata do",
        "bata de",
        "batao",
        "batado",
        "de do",
        "de dena",
        "dedo",
        "paise dena",
        "paise bhej",
        "paisa bhej",
        "dekh lena",
        "dekh lo",
        "dekho",
        "suno",
        "le aana",
        "le aao",
        "la dena",
        "भेज दो",
        "भेज देना",
        "भेजो",
        "भेजना",
        "कर दो",
        "कर देना",
        "करो",
        "बताओ",
        "बता दो",
        "बता देना",
        "बताना",
        "दे दो",
        "दे देना",
        "देख लो",
        "देखो",
        "सुनो",
    )

    val requestStarts = setOf(
        "send",
        "share",
        "bring",
        "check",
        "review",
        "sign",
        "reply",
        "text",
        "tell",
        "give",
        "get",
        "pay",
        "book",
        "fix",
        "update",
        "forward",
        "confirm",
        "approve",
        "buy",
        "pick",
        "look",
        "remind",
        "ping",
        "drop",
    )

    val questionStarts = listOf(
        "what",
        "when",
        "where",
        "who",
        "whom",
        "whose",
        "why",
        "how",
        "which",
        "did",
        "does",
        "do you",
        "do we",
        "are you",
        "are we",
        "is it",
        "is this",
        "is that",
        "was it",
        "were you",
        "will it",
        "should i",
        "should we",
        "shall we",
        "shall i",
        "can i",
        "can we",
        "could i",
        "could we",
        "have you",
        "has it",
        "any update",
        "any news",
        "kya",
        "kab",
        "kahan",
        "kaha",
        "kidhar",
        "kaise",
        "kaun",
        "kyun",
        "kyu",
        "kitna",
        "kitne",
        "kitni",
        "क्या",
        "कब",
        "कहाँ",
        "कैसे",
        "कौन",
        "क्यों",
        "कितना",
        "कितने",
        "कितनी",
    )

    val questionPhrases = listOf(
        "how are you",
        "where are you",
        "what time",
        "what about you",
        "kya hua",
        "kya kar",
        "kaisa hai",
        "kaisi hai",
        "kaise ho",
        "kya haal",
        "hai kya",
        "ho kya",
        "kab tak",
        "है क्या",
    )

    val questionEnds = setOf(
        "kya",
        "क्या",
    )

    val invitePhrases = listOf(
        "you in",
        "join us",
        "join me",
        "come over",
        "come to",
        "are you free",
        "you free",
        "free tonight",
        "free today",
        "free tomorrow",
        "free this",
        "wanna come",
        "want to come",
        "wanna join",
        "want to join",
        "lets go",
        "let's go",
        "lets meet",
        "let's meet",
        "coming tonight",
        "coming today",
        "coming tomorrow",
        "party tonight",
        "dinner tonight",
        "dinner tomorrow",
        "chalo",
        "chalein",
        "chalega kya",
        "aaja",
        "aa ja",
        "aa jao",
        "aajao",
        "aa jana",
        "milte hain",
        "milna hai",
        "mil sakte",
        "चलो",
        "चलें",
        "आ जाओ",
        "आजा",
        "मिलते हैं",
    )

    val deadlinePhrases = listOf(
        "by tomorrow",
        "by tonight",
        "by today",
        "by eod",
        "by eow",
        "by noon",
        "by morning",
        "by evening",
        "by monday",
        "by tuesday",
        "by wednesday",
        "by thursday",
        "by friday",
        "by saturday",
        "by sunday",
        "before tomorrow",
        "before tonight",
        "before eod",
        "before noon",
        "before monday",
        "before tuesday",
        "before wednesday",
        "before thursday",
        "before friday",
        "before saturday",
        "before sunday",
        "due today",
        "due tomorrow",
        "due tonight",
        "due by",
        "due on",
        "is due",
        "are due",
        "deadline",
        "asap",
        "urgent",
        "urgently",
        "jaldi",
        "kal tak",
        "aaj tak",
        "shaam tak",
        "subah tak",
        "raat tak",
        "कल तक",
        "आज तक",
        "जल्दी",
    )

    val notAskPhrases = listOf(
        "can you believe",
        "could you believe",
        "would you believe",
        "yes please",
        "why not",
        "how sweet",
        "how nice",
        "how cute",
        "how cool",
        "how lovely",
        "how funny",
        "what a",
        "kya baat",
        "get well",
        "get some rest",
        "no need",
        "no worries",
        "koi nahi",
        "koi baat nahi",
        "nahi chahiye",
        "chalo theek",
        "chalo bye",
        "chal bye",
    )

    val ackWords = setOf(
        "thanks",
        "thank",
        "thanku",
        "thankyou",
        "thx",
        "ty",
        "tysm",
        "tq",
        "shukriya",
        "dhanyawad",
        "dhanyavaad",
        "appreciated",
        "appreciate",
        "it",
        "you",
        "so",
        "much",
        "very",
        "a",
        "lot",
        "ok",
        "okay",
        "okie",
        "okey",
        "oki",
        "okk",
        "okkk",
        "okkkk",
        "k",
        "kk",
        "kkk",
        "hmm",
        "hmmm",
        "hm",
        "mm",
        "mhm",
        "cool",
        "nice",
        "great",
        "awesome",
        "perfect",
        "super",
        "sure",
        "fine",
        "done",
        "yes",
        "yep",
        "yup",
        "yeah",
        "yea",
        "ya",
        "haan",
        "haa",
        "han",
        "ji",
        "noted",
        "got",
        "alright",
        "right",
        "understood",
        "roger",
        "ofc",
        "of",
        "course",
        "correct",
        "exactly",
        "true",
        "good",
        "and",
        "sir",
        "bro",
        "bhai",
        "dear",
        "mam",
        "धन्यवाद",
        "शुक्रिया",
        "ठीक",
        "है",
        "हाँ",
        "हां",
        "जी",
        "ओके",
    )

    val thankWords = setOf(
        "thanks",
        "thank",
        "thanku",
        "thankyou",
        "thx",
        "ty",
        "tysm",
        "tq",
        "shukriya",
        "dhanyawad",
        "dhanyavaad",
        "appreciated",
        "धन्यवाद",
        "शुक्रिया",
    )

    val closerPhrases = listOf(
        "see you",
        "see ya",
        "see u",
        "cya",
        "good night",
        "goodnight",
        "gn",
        "gm",
        "good morning",
        "bye",
        "byee",
        "byeee",
        "goodbye",
        "take care",
        "tc",
        "talk later",
        "talk soon",
        "ttyl",
        "no worries",
        "no problem",
        "np",
        "all good",
        "sounds good",
        "will do",
        "on my way",
        "omw",
        "reached",
        "haha",
        "hahaha",
        "hehe",
        "lol",
        "lmao",
        "rofl",
        "theek hai",
        "thik hai",
        "thikh hai",
        "tik hai",
        "accha",
        "achha",
        "acha",
        "koi nahi",
        "koi baat nahi",
        "ho gaya",
        "ho gya",
        "mil gaya",
        "mil gya",
        "kar diya",
        "bhej diya",
        "शुभ रात्रि",
        "ठीक है",
        "अच्छा",
        "हो गया",
        "मिल गया",
    )

    val stickerWords = setOf(
        "sticker",
        "gif",
    )

    private const val MAX_ACK_TOKENS = 8
    private const val MAX_CLOSER_TOKENS = 10

    private val notWord = Regex("[^\\p{L}\\p{M}\\p{N}']+")

    private fun tokens(text: String): List<String> =
        text.lowercase().replace('\u2019', '\'').split(notWord).filter { it.isNotEmpty() }

    private fun hasQuestionMark(text: String) =
        text.contains('?') || text.contains('\uFF1F') || text.contains('\u061F')

    private fun startsWithDigit(t: String) = t.isNotEmpty() && t[0] in '0'..'9'

    private fun hasAny(table: Collection<String>, s: String) = table.any { s.contains(" $it ") }

    private fun startsWithAny(table: Collection<String>, s: String) =
        table.any { s.startsWith(" $it ") }

    private fun hasNumericDeadline(tokens: List<String>): Boolean {
        for (i in tokens.indices) {
            if (tokens[i] != "by" && tokens[i] != "before") continue
            var j = i + 1
            while (j <= i + 2 && j < tokens.size) {
                if (startsWithDigit(tokens[j])) return true
                j++
            }
        }
        return false
    }

    // The patterns in one_time_codes.dart.
    private val codeCue = Regex(
        "\\botp\\b|\\b2fa\\b|\\bpasscode\\b|\\bone[\\s-]?time\\s+(?:code|password|pin)\\b" +
            "|\\b(?:verification|verify|security|login|log[\\s-]?in|sign[\\s-]?in|auth" +
            "|authentication|confirmation|access|activation)\\s+(?:code|pin)\\b" +
            "|\\byour\\s+(?:\\w+\\s+){0,3}(?:code|pin)\\b" +
            "|\\b(?:code|pin)\\s*(?:is\\b|hai\\b|:|=)" +
            "|\\bdo\\s*n[o'’]?t\\s+share\\b|\\bnever\\s+share\\b|\\bshare\\s+mat\\b" +
            "|ओटीपी|सत्यापन|कोड",
        RegexOption.IGNORE_CASE,
    )
    private val codeToken = Regex(
        "(?<![\\w/₹$]|\\d[.,-])" +
            "(?:[A-Z]{1,3}-\\d{4,8}" +
            "|\\d{3,4}[ -]\\d{3,4}" +
            "|\\d(?: \\d){3,7}" +
            "|\\d{4,8}" +
            "|(?=[A-Z0-9]*\\d)(?=[A-Z0-9]*[A-Z])[A-Z0-9]{6,10})" +
            "(?![\\w/]|[.,-]\\d)",
    )
    private val moneyBefore = Regex("(?:\\brs\\.?|\\binr|₹|\\$)\\s*$", RegexOption.IGNORE_CASE)

    private fun hasOneTimeCode(text: String): Boolean {
        val cues = codeCue.findAll(text).toList()
        if (cues.isEmpty()) return false
        return codeToken.findAll(text).any { m ->
            val near = cues.any { c ->
                m.range.last + 1 > c.range.first - 60 && m.range.first < c.range.last + 1 + 100
            }
            near && !moneyBefore.containsMatchIn(text.substring(maxOf(0, m.range.first - 8), m.range.first))
        }
    }

    /** What the rules alone make of [text]. */
    fun kindOf(text: String): Kind {
        val trimmed = text.trim()
        if (hasOneTimeCode(trimmed)) return Kind.code
        val tokens = tokens(trimmed)
        if (tokens.isEmpty()) return if (hasQuestionMark(trimmed)) Kind.question else Kind.emojiOnly
        val s = " " + tokens.joinToString(" ") + " "
        if (tokens.size == 1 && tokens[0] in stickerWords) return Kind.emojiOnly

        if (hasAny(callPhrases, s)) return Kind.call
        if (tokens[0] in callStarts) return Kind.call

        if (!hasAny(notAskPhrases, s)) {
            if (hasAny(requestPhrases, s)) return Kind.request
            if (tokens[0] in requestStarts) return Kind.request
            if (hasQuestionMark(trimmed)) return Kind.question
            if (hasAny(invitePhrases, s)) return Kind.invite
            if (startsWithAny(questionStarts, s)) return Kind.question
            if (hasAny(questionPhrases, s)) return Kind.question
            if (tokens.last() in questionEnds) return Kind.question
            if (hasAny(deadlinePhrases, s)) return Kind.deadline
            if (hasNumericDeadline(tokens)) return Kind.deadline
        }

        if (tokens.size <= MAX_ACK_TOKENS && tokens.all { it in ackWords }) return Kind.ack
        if (tokens.size <= MAX_CLOSER_TOKENS) {
            if (hasAny(thankWords, s)) return Kind.ack
            if (hasAny(closerPhrases, s)) return Kind.closer
        }
        return Kind.unsure
    }

    /** [addressed] is the message's Addressed name: "direct", "mentioned", … */
    fun classify(text: String, isGroup: Boolean, addressed: String?): Result {
        val kind = kindOf(text)
        val asks = kind == Kind.question || kind == Kind.request || kind == Kind.call ||
            kind == Kind.invite || kind == Kind.deadline
        val finalKind = if (asks && addressed == "mentioned") Kind.mention else kind
        return Result(finalKind, asks || kind == Kind.unsure)
    }
}
