-- Runtime strings in Lithuanian and English. The wording is the VS Code extension's
-- (apps/vscode/src/i18n), itself from the web app's messages, so every client says the same.
-- The language follows the account (`/me`), the `language` setting overrides it; signed out,
-- Neovim's own language decides (Lithuanian for `lt`, else English).

local M = {}

local en = {
  ["view.courses"] = "Courses",
  ["view.results"] = "Tests and results",
  ["view.submissions"] = "Your submissions",

  ["auth.signIn"] = "Sign in",
  ["auth.waiting"] = "Allow access in the browser to sign in…",
  ["auth.openUrl"] = "If the browser didn't open, go to {url}",
  ["auth.deviceTitle"] = "Sign in to Programavimas",
  ["auth.deviceWaiting"] = "Waiting for you to allow access…",
  ["auth.signedIn"] = "Signed in as {name}.",
  ["auth.failed"] = "Sign-in didn't complete. Try again.",
  ["auth.timedOut"] = "Sign-in timed out. Try again.",
  ["auth.denied"] = "Access wasn't allowed, so you're not signed in.",
  ["auth.cancelled"] = "Sign-in cancelled.",
  ["auth.scope"] = "This version needs new permissions. Sign in again – your code is saved in its files.",
  ["auth.expired"] = "You've been signed out. Sign in again – your code is saved in its files.",
  ["auth.signedOutFiles"] = "Signed out. Your solution files stay on this computer.",
  ["auth.notSignedIn"] = "You're not signed in. Run :Programavimas login",
  ["auth.badServer"] = "The server setting {server} isn't usable: https, or http for localhost only.",
  ["auth.badMetadata"] = "The server's sign-in settings don't match {server}.",

  ["account.signedInAs"] = "Signed in as {name}",
  ["account.server"] = "Server: {server}",
  ["account.folder"] = "Solutions: {folder}",
  ["account.noFolder"] = "Solutions folder: not chosen yet",
  ["account.openInBrowser"] = "Open in browser",
  ["account.changeFolder"] = "Change solutions folder…",
  ["account.signOut"] = "Sign out",

  ["error.network"] = "Couldn't reach the server. Check your connection and try again.",
  ["error.invalid"] = "The server sent something this version doesn't understand. Update the plugin.",
  ["error.curl"] = "curl wasn't found. Install curl to use Programavimas.",

  ["courses.empty"] = "You have no courses yet.",
  ["courses.loading"] = "Loading…",
  ["courses.loadFailed"] = "Couldn't load your courses.",
  ["courses.spreadsheet"] = "Excel tasks open in the browser.",
  ["courses.topicMode.test"] = "Assessment",
  ["courses.passed"] = "{passed} of {total}",
  ["courses.hidden"] = "{count} more not open yet",
  ["courses.help"] = "<CR> open or expand · l/h expand/collapse · r refresh · gx open in browser · P create course folders · q close",
  ["help.hint"] = "? keys",

  ["status.not_started"] = "Not started",
  ["status.attempted"] = "Attempted",
  ["status.attemptedTests"] = "{passed} of {total} tests pass",
  ["status.complete"] = "Solved",
  ["status.completeLate"] = "Solved after the deadline",
  ["status.locked"] = "Not open yet",

  ["verdict.accepted"] = "Accepted",
  ["verdict.wrong_answer"] = "Wrong answer",
  ["verdict.presentation_error"] = "Presentation error",
  ["verdict.compilation_error"] = "Compilation error",
  ["verdict.runtime_error"] = "Runtime error",
  ["verdict.time_limit_exceeded"] = "Time limit exceeded",
  ["verdict.memory_limit_exceeded"] = "Memory limit exceeded",
  ["verdict.idleness_limit_exceeded"] = "Idleness limit exceeded",
  ["verdict.output_limit_exceeded"] = "Output limit exceeded",
  ["verdict.security_violation"] = "Security violation",
  ["verdict.checker_error"] = "Check failed",
  ["verdict.system_error"] = "System error",

  ["judging.queued"] = "Waiting",
  ["judging.compiling"] = "Compiling",
  ["judging.testing"] = "Testing",
  ["judging.finished"] = "Checked",
  ["judging.failed"] = "System error",
  ["judging.cancelled"] = "Cancelled",
  ["judging.sending"] = "Sending…",

  ["due.overdue"] = "Overdue · {date}",
  ["due.today"] = "Today, {time}",
  ["due.tomorrow"] = "Tomorrow, {time}",

  ["actions.runSamples"] = "Run samples",
  ["actions.runCustom"] = "Run with custom input",
  ["actions.submit"] = "Submit",
  ["mode.practice"] = "Practice · not graded",
  ["mode.graded"] = "Graded · uses an attempt",
  ["attempts.short"] = "Attempts left: {left} of {total}",
  ["attempts.none"] = "No attempts left today",

  ["errors.unauthenticated"] = "You've been signed out. Sign in again – your code is saved in its files.",
  ["errors.notFound"] = "This problem is no longer available to you.",
  ["errors.invalid"] = "The request was invalid. Refresh and try again.",
  ["errors.failed"] = "Couldn't send. Your code is saved – try again.",
  ["errors.language"] = "This programming language isn't allowed for this problem.",
  ["errors.emptySource"] = "The code is empty.",
  ["errors.sourceTooLarge"] = "The code is too long: at most {limit} KB.",
  ["errors.inputTooLarge"] = "The input is too long: at most {limit} KB.",
  ["errors.locked"] = "This problem isn't open yet.",
  ["errors.closed"] = "Submissions closed {date}.",
  ["errors.closedNoDate"] = "Submissions are closed.",
  ["errors.noAttempts"] = "No attempts left today. Next attempt: {date}.",
  ["errors.noAttemptsNoDate"] = "No attempts left today.",
  ["errors.busy"] = "Wait for your previous submissions to be checked.",
  ["errors.judging"] = "Your previous submission of this problem is still being judged. Submit again once it's checked.",
  ["errors.rateLimited"] = "Too many requests in a short time. Wait {seconds} s and try again.",
  ["errors.rateLimitedNoTime"] = "Too many requests in a short time. Wait a moment and try again.",
  ["errors.noSamples"] = "This problem has no sample tests. Run your program with custom input.",
  ["errors.customDuringExam"] = "During a test, programs can only be run with the samples.",
  ["errors.versionChanged"] = "This problem was updated. Refresh to see the new statement – your code is kept.",

  ["results.idleTitle"] = "Nothing run yet",
  ["results.idleBody"] = "Run the samples as often as you like, then submit. Results appear here.",
  ["results.samplesPassed"] = "{passed} of {total} samples",
  ["results.testsChip"] = "{passed} of {total} tests",
  ["results.maxTime"] = "up to {ms} ms",
  ["results.maxMemory"] = "up to {mb} MB",
  ["results.samplesTitle"] = "Samples",
  ["results.testsTitle"] = "Tests",
  ["results.customTitle"] = "Custom input",
  ["results.refusedTitle"] = "Couldn't start",
  ["results.firstDifference"] = "First difference on line {line}: expected {expected}, got {actual}",
  ["results.missingLine"] = "First difference on line {line}: expected {expected}, your program printed no such line",
  ["results.extraLine"] = "First difference on line {line}: the output should end here, got {actual}",
  ["results.points"] = "Points: {score} of {max}",
  ["results.firstFailure"] = "first failure on test {number}",
  ["results.sample"] = "Sample {number}",
  ["results.test"] = "Test {number}",
  ["results.input"] = "Input",
  ["results.expected"] = "Expected output",
  ["results.actual"] = "Your output",
  ["results.stderr"] = "Error output",
  ["results.checker"] = "Checker message",
  ["results.empty"] = "(empty)",
  ["results.truncated"] = "Long data is shortened here.",
  ["results.hidden"] = "Test details are hidden by the course settings.",
  ["results.notRun"] = "Not run",
  ["results.compilerMessages"] = "Compiler messages are marked in the code (:lua vim.diagnostic.setqflist()).",
  ["results.general"] = "Compiler",
  ["results.customOutput"] = "Program output",
  ["results.outputFile"] = "Output file {name}",
  ["results.noOutput"] = "The program printed nothing.",
  ["results.busyPractice"] = "The judge is busy or offline. Run your program again in a moment.",
  ["results.busyGraded"] = "The judge is busy or offline. Your submission is saved and will be judged as soon as it's available.",
  ["results.systemPractice"] = "The run failed on our side. Run it again.",
  ["results.cancelled"] = "This run was cancelled because a newer one started.",
  ["results.lost"] = "Couldn't follow this run any more. Open the problem again.",
  ["results.time"] = "{ms} ms",
  ["results.memory"] = "{mb} MB",
  ["results.help"] = "<CR> show or hide a test · r run samples · q close",

  ["statement.stdio"] = "Standard input and output",
  ["statement.notReady"] = "The statement isn't ready here yet. Open the problem in the browser.",
  ["statement.languageElsewhere"] = "{name} (browser only)",
  ["statement.help"] = "o open the solution · gb open in browser · r refresh · q close",

  ["open.prompt"] = "Open a problem",
  ["open.language"] = "Choose a programming language",
  ["open.notSolution"] = "Open a solution file first (:Programavimas open).",
  ["open.customInput"] = "Write your input in {file}, then run again.",
  ["open.loadFailed"] = "Couldn't open this problem.",
  ["open.noLanguage"] = "Neovim can't edit the languages allowed for this problem yet. Open it in the browser.",
  ["open.started"] = "Started from your {source}.",
  ["open.source.draft"] = "draft saved on the server",
  ["open.source.submission"] = "latest submission",

  ["drafts.updated"] = "{file} now holds your draft saved at {time}.",
  ["drafts.differs"] = "{file} differs from your draft saved elsewhere at {time}",
  ["drafts.useSaved"] = "Use the saved draft ({time})",
  ["drafts.keep"] = "Keep this file",
  ["drafts.compare"] = "Compare",
  ["drafts.compareSaved"] = " Draft on the server · saved {time}",
  ["drafts.compareFile"] = " This file · {file}",
  ["drafts.decideLater"] = "Nothing changed. :Programavimas sync asks again.",
  ["drafts.tooLarge"] = "{file} is too large to save as a draft on the server.",
  ["drafts.notMain"] = "Drafts sync for a problem's main file (main.cpp, main.py or main.cs).",

  ["folder.pickTitle"] = "Where should solutions live?",
  ["folder.current"] = "This folder · {path}",
  ["folder.other"] = "Choose another folder…",
  ["folder.input"] = "Solutions folder: ",
  ["folder.changed"] = "New solutions go to {path}. Existing folders are not moved.",
  ["folder.notCreated"] = "Couldn't create the folder {path}.",

  ["course.prepared"] = "Created problem folders: {created}. Already there: {existing}.",

  ["submissions.empty"] = "You haven't submitted anything yet.",
  ["submissions.prompt"] = "Your recent submissions",

  ["statement.image"] = "Image",
  ["statement.keys"] = "<CR> or gx open the link · o open the solution · gb open in browser · r refresh · q close",
  ["results.inputFrom"] = "Input · {file}",
  ["auth.deviceOpen"] = "On any device, open",
  ["auth.deviceEnter"] = "and enter this code:",
  ["auth.deviceCancel"] = "q cancel",

  -- Dates and deadlines as the web shows them (apps/web/src/features/shared/due-date.tsx,
  -- i18n/formats.ts): "Dec 1"; within a week "In 3 days"; after a date, how far off.
  ["date.months"] = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" },
  ["date.day"] = "{month} {day}",
  ["date.dayYear"] = "{month} {day}, {year}",
  ["date.dayTime"] = "{date}, {time}",
  ["due.inDays"] = { one = "In {count} day", other = "In {count} days" },
  ["due.laterDays"] = { one = "in {count} day", other = "in {count} days" },
  ["due.laterWeeks"] = { one = "in {count} week", other = "in {count} weeks" },
  ["due.laterMonths"] = { one = "in {count} month", other = "in {count} months" },
  ["statement.seconds"] = "{seconds} s",
  ["statement.megabytes"] = "{mb} MB",
  ["statement.gigabytes"] = "{gb} GB",
  ["statement.attempts"] = "{left} of {total} left",
}

local lt = {
  ["view.courses"] = "Kursai",
  ["view.results"] = "Testai ir patikra",
  ["view.submissions"] = "Jūsų sprendimai",

  ["auth.signIn"] = "Prisijungti",
  ["auth.waiting"] = "Leiskite prieigą naršyklėje, kad prisijungtumėte…",
  ["auth.openUrl"] = "Jei naršyklė neatsidarė, eikite į {url}",
  ["auth.deviceTitle"] = "Prisijungimas prie Programavimas",
  ["auth.deviceWaiting"] = "Laukiama, kol leisite prieigą…",
  ["auth.signedIn"] = "Prisijungta kaip {name}.",
  ["auth.failed"] = "Prisijungti nepavyko. Bandykite dar kartą.",
  ["auth.timedOut"] = "Baigėsi prisijungimui skirtas laikas. Bandykite dar kartą.",
  ["auth.denied"] = "Prieiga nesuteikta, todėl neprisijungta.",
  ["auth.cancelled"] = "Prisijungimas atšauktas.",
  ["auth.scope"] = "Šiai versijai reikia naujų leidimų. Prisijunkite iš naujo – kodas išsaugotas failuose.",
  ["auth.expired"] = "Sesija baigėsi. Prisijunkite iš naujo – kodas išsaugotas failuose.",
  ["auth.signedOutFiles"] = "Atsijungta. Sprendimų failai lieka šiame kompiuteryje.",
  ["auth.notSignedIn"] = "Neprisijungta. Paleiskite :Programavimas login",
  ["auth.badServer"] = "Serverio nustatymas {server} netinka: https arba http tik localhost.",
  ["auth.badMetadata"] = "Serverio prisijungimo nustatymai neatitinka {server}.",

  ["account.signedInAs"] = "Prisijungta kaip {name}",
  ["account.server"] = "Serveris: {server}",
  ["account.folder"] = "Sprendimai: {folder}",
  ["account.noFolder"] = "Sprendimų aplankas dar nepasirinktas",
  ["account.openInBrowser"] = "Atidaryti naršyklėje",
  ["account.changeFolder"] = "Pakeisti sprendimų aplanką…",
  ["account.signOut"] = "Atsijungti",

  ["error.network"] = "Nepavyko pasiekti serverio. Patikrinkite ryšį ir pakartokite.",
  ["error.invalid"] = "Serveris atsiuntė duomenų, kurių ši versija nesupranta. Atnaujinkite įskiepį.",
  ["error.curl"] = "Nerasta programa curl. Įdiekite curl, kad galėtumėte naudotis Programavimas.",

  ["courses.empty"] = "Kursų dar neturite.",
  ["courses.loading"] = "Įkeliama…",
  ["courses.loadFailed"] = "Nepavyko įkelti kursų.",
  ["courses.spreadsheet"] = "Excel užduotys atidaromos naršyklėje.",
  ["courses.topicMode.test"] = "Kontrolinis darbas",
  ["courses.passed"] = "{passed} iš {total}",
  ["courses.hidden"] = "dar {count} neatidarytos",
  ["courses.help"] = "<CR> atidaryti ar išskleisti · l/h išskleisti/suskleisti · r atnaujinti · gx atidaryti naršyklėje · P sukurti kurso aplankus · q uždaryti",
  ["help.hint"] = "? klavišai",

  ["status.not_started"] = "Nepradėta",
  ["status.attempted"] = "Sprendžiama",
  ["status.attemptedTests"] = "Išlaikyta testų: {passed} iš {total}",
  ["status.complete"] = "Išspręsta",
  ["status.completeLate"] = "Išspręsta po termino",
  ["status.locked"] = "Dar neatidaryta",

  ["verdict.accepted"] = "Priimta",
  ["verdict.wrong_answer"] = "Neteisingas atsakymas",
  ["verdict.presentation_error"] = "Netinkamas rezultatų formatas",
  ["verdict.compilation_error"] = "Kompiliavimo klaida",
  ["verdict.runtime_error"] = "Vykdymo klaida",
  ["verdict.time_limit_exceeded"] = "Viršyta laiko riba",
  ["verdict.memory_limit_exceeded"] = "Viršyta atminties riba",
  ["verdict.idleness_limit_exceeded"] = "Viršyta laukimo riba",
  ["verdict.output_limit_exceeded"] = "Viršyta išvesties riba",
  ["verdict.security_violation"] = "Draudžiamas veiksmas",
  ["verdict.checker_error"] = "Tikrinimo klaida",
  ["verdict.system_error"] = "Sistemos klaida",

  ["judging.queued"] = "Eilėje",
  ["judging.compiling"] = "Kompiliuojama",
  ["judging.testing"] = "Testuojama",
  ["judging.finished"] = "Patikrinta",
  ["judging.failed"] = "Sistemos klaida",
  ["judging.cancelled"] = "Atšaukta",
  ["judging.sending"] = "Siunčiama…",

  ["due.overdue"] = "Pavėluota · {date}",
  ["due.today"] = "Šiandien, {time}",
  ["due.tomorrow"] = "Rytoj, {time}",

  ["actions.runSamples"] = "Paleisti su pavyzdžiais",
  ["actions.runCustom"] = "Paleisti su savais duomenimis",
  ["actions.submit"] = "Pateikti sprendimą",
  ["mode.practice"] = "Paleidimas · nevertinamas",
  ["mode.graded"] = "Vertinama · naudojamas bandymas",
  ["attempts.short"] = "Liko bandymų: {left} iš {total}",
  ["attempts.none"] = "Šiandienos bandymai išnaudoti",

  ["errors.unauthenticated"] = "Sesija baigėsi. Prisijunkite iš naujo – kodas išsaugotas failuose.",
  ["errors.notFound"] = "Ši užduotis jums nebepasiekiama.",
  ["errors.invalid"] = "Užklausa netinkama. Atnaujinkite ir pakartokite.",
  ["errors.failed"] = "Išsiųsti nepavyko. Kodas išsaugotas – pakartokite.",
  ["errors.language"] = "Šiai užduočiai ši programavimo kalba neleidžiama.",
  ["errors.emptySource"] = "Kodas tuščias.",
  ["errors.sourceTooLarge"] = "Kodas per ilgas: daugiausia {limit} KB.",
  ["errors.inputTooLarge"] = "Duomenys per ilgi: daugiausia {limit} KB.",
  ["errors.locked"] = "Ši užduotis dar neatidaryta.",
  ["errors.closed"] = "Sprendimų priėmimas baigėsi {date}.",
  ["errors.closedNoDate"] = "Sprendimų priėmimas baigėsi.",
  ["errors.noAttempts"] = "Šiandienos bandymai išnaudoti. Kitas bandymas – {date}.",
  ["errors.noAttemptsNoDate"] = "Šiandienos bandymai išnaudoti.",
  ["errors.busy"] = "Palaukite, kol bus patikrinti ankstesni sprendimai.",
  ["errors.judging"] = "Ankstesnis šios užduoties sprendimas dar tikrinamas. Pateikite iš naujo, kai jis bus patikrintas.",
  ["errors.rateLimited"] = "Per daug užklausų per trumpą laiką. Palaukite {seconds} s ir pakartokite.",
  ["errors.rateLimitedNoTime"] = "Per daug užklausų per trumpą laiką. Palaukite akimirką ir pakartokite.",
  ["errors.noSamples"] = "Ši užduotis neturi pavyzdinių testų. Paleiskite programą su savais duomenimis.",
  ["errors.customDuringExam"] = "Kontrolinio darbo metu programą galima paleisti tik su pavyzdžiais.",
  ["errors.versionChanged"] = "Užduotis atnaujinta. Atnaujinkite, kad matytumėte naują sąlygą – kodas išsaugotas.",

  ["results.idleTitle"] = "Dar nieko nepaleista",
  ["results.idleBody"] = "Paleiskite pavyzdžius kiek norite, tada pateikite sprendimą. Rezultatai bus rodomi čia.",
  ["results.samplesPassed"] = "{passed} iš {total} pavyzdžių",
  ["results.testsChip"] = "{passed} iš {total} testų",
  ["results.maxTime"] = "iki {ms} ms",
  ["results.maxMemory"] = "iki {mb} MB",
  ["results.samplesTitle"] = "Pavyzdžiai",
  ["results.testsTitle"] = "Testai",
  ["results.customTitle"] = "Savi duomenys",
  ["results.refusedTitle"] = "Nepavyko paleisti",
  ["results.firstDifference"] = "Pirmas skirtumas – {line} eilutėje: laukta {expected}, gauta {actual}",
  ["results.missingLine"] = "Pirmas skirtumas – {line} eilutėje: laukta {expected}, programa tokios eilutės neišvedė",
  ["results.extraLine"] = "Pirmas skirtumas – {line} eilutėje: išvestis čia turėjo baigtis, gauta {actual}",
  ["results.points"] = "Taškai: {score} iš {max}",
  ["results.firstFailure"] = "pirmasis neišlaikytas testas – {number}",
  ["results.sample"] = "Pavyzdys {number}",
  ["results.test"] = "Testas {number}",
  ["results.input"] = "Pradiniai duomenys",
  ["results.expected"] = "Laukiami rezultatai",
  ["results.actual"] = "Programos rezultatai",
  ["results.stderr"] = "Klaidų išvestis",
  ["results.checker"] = "Tikrintuvo pranešimas",
  ["results.empty"] = "(tuščia)",
  ["results.truncated"] = "Ilgi duomenys čia sutrumpinti.",
  ["results.hidden"] = "Testų duomenys paslėpti pagal kurso nustatymus.",
  ["results.notRun"] = "Nevykdytas",
  ["results.compilerMessages"] = "Kompiliatoriaus pranešimai pažymėti kode (:lua vim.diagnostic.setqflist()).",
  ["results.general"] = "Kompiliatorius",
  ["results.customOutput"] = "Programos rezultatai",
  ["results.outputFile"] = "Rezultatų failas {name}",
  ["results.noOutput"] = "Programa nieko neišvedė.",
  ["results.busyPractice"] = "Tikrinimo sistema šiuo metu užimta arba nepasiekiama. Paleiskite programą dar kartą po kelių akimirkų.",
  ["results.busyGraded"] = "Tikrinimo sistema šiuo metu užimta arba nepasiekiama. Sprendimas išsaugotas ir bus patikrintas, kai tik ji atsilaisvins.",
  ["results.systemPractice"] = "Programos paleisti nepavyko dėl sistemos klaidos. Paleiskite ją dar kartą.",
  ["results.cancelled"] = "Šis paleidimas atšauktas, nes pradėtas naujas.",
  ["results.lost"] = "Šio paleidimo būsenos nebegaunama. Atidarykite užduotį iš naujo.",
  ["results.time"] = "{ms} ms",
  ["results.memory"] = "{mb} MB",
  ["results.help"] = "<CR> rodyti ar slėpti testą · r paleisti pavyzdžius · q uždaryti",

  ["statement.stdio"] = "Standartinė įvestis ir išvestis",
  ["statement.notReady"] = "Sąlyga čia dar neparengta. Atidarykite užduotį naršyklėje.",
  ["statement.languageElsewhere"] = "{name} (tik naršyklėje)",
  ["statement.help"] = "o atidaryti sprendimą · gb atidaryti naršyklėje · r atnaujinti · q uždaryti",

  ["open.prompt"] = "Atidaryti užduotį",
  ["open.language"] = "Pasirinkite programavimo kalbą",
  ["open.notSolution"] = "Pirmiausia atidarykite sprendimo failą (:Programavimas open).",
  ["open.customInput"] = "Įrašykite savo duomenis į {file} ir paleiskite dar kartą.",
  ["open.loadFailed"] = "Nepavyko atidaryti užduoties.",
  ["open.noLanguage"] = "Neovim dar nepalaiko šiai užduočiai leidžiamų programavimo kalbų. Atidarykite ją naršyklėje.",
  ["open.started"] = "Pradėta nuo jūsų {source}.",
  ["open.source.draft"] = "serveryje išsaugoto juodraščio",
  ["open.source.submission"] = "naujausio pateikto sprendimo",

  ["drafts.updated"] = "{file} atnaujintas pagal juodraštį, išsaugotą {time}.",
  ["drafts.differs"] = "{file} skiriasi nuo juodraščio, kitur išsaugoto {time}",
  ["drafts.useSaved"] = "Naudoti išsaugotą juodraštį ({time})",
  ["drafts.keep"] = "Palikti šį failą",
  ["drafts.compare"] = "Palyginti",
  ["drafts.compareSaved"] = " Juodraštis serveryje · išsaugotas {time}",
  ["drafts.compareFile"] = " Šis failas · {file}",
  ["drafts.decideLater"] = "Nieko nepakeista. :Programavimas sync paklaus dar kartą.",
  ["drafts.tooLarge"] = "{file} per didelis, kad būtų išsaugotas serveryje kaip juodraštis.",
  ["drafts.notMain"] = "Juodraščiai sinchronizuojami užduoties pagrindiniam failui (main.cpp, main.py arba main.cs).",

  ["folder.pickTitle"] = "Kur laikyti sprendimus?",
  ["folder.current"] = "Šis aplankas · {path}",
  ["folder.other"] = "Pasirinkti kitą aplanką…",
  ["folder.input"] = "Sprendimų aplankas: ",
  ["folder.changed"] = "Nauji sprendimai bus kuriami aplanke {path}. Esami aplankai neperkeliami.",
  ["folder.notCreated"] = "Nepavyko sukurti aplanko {path}.",

  ["course.prepared"] = "Sukurta užduočių aplankų: {created}. Jau buvo: {existing}.",

  ["submissions.empty"] = "Dar nieko nepateikėte.",
  ["submissions.prompt"] = "Naujausi jūsų sprendimai",

  ["statement.image"] = "Paveikslėlis",
  ["statement.keys"] = "<CR> ar gx atidaryti nuorodą · o atidaryti sprendimą · gb atidaryti naršyklėje · r atnaujinti · q uždaryti",
  ["results.inputFrom"] = "Pradiniai duomenys · {file}",
  ["auth.deviceOpen"] = "Bet kuriame įrenginyje atidarykite",
  ["auth.deviceEnter"] = "ir įveskite šį kodą:",
  ["auth.deviceCancel"] = "q atšaukti",

  ["date.months"] = {
    "sausio", "vasario", "kovo", "balandžio", "gegužės", "birželio",
    "liepos", "rugpjūčio", "rugsėjo", "spalio", "lapkričio", "gruodžio",
  },
  ["date.day"] = "{month} {day} d.",
  ["date.dayYear"] = "{year} m. {month} {day} d.",
  ["date.dayTime"] = "{date} {time}",
  ["due.inDays"] = { one = "Po {count} dienos", few = "Po {count} dienų", other = "Po {count} dienų" },
  ["due.laterDays"] = { one = "po {count} dienos", few = "po {count} dienų", other = "po {count} dienų" },
  ["due.laterWeeks"] = { one = "po {count} savaitės", few = "po {count} savaičių", other = "po {count} savaičių" },
  ["due.laterMonths"] = { one = "po {count} mėnesio", few = "po {count} mėnesių", other = "po {count} mėnesių" },
  ["statement.seconds"] = "{seconds} s",
  ["statement.megabytes"] = "{mb} MB",
  ["statement.gigabytes"] = "{gb} GB",
  ["statement.attempts"] = "Liko {left} iš {total}",
}

M.catalogs = { en = en, lt = lt }

---@type "lt"|"en"|nil  The account's language from `/me`, once known
M.account = nil

--- The language strings are shown in now.
---@return "lt"|"en"
function M.language()
  local setting = require("programavimas.config").options.language
  if setting == "lt" or setting == "en" then return setting end
  if M.account then return M.account end
  local env = vim.v.lang ~= "" and vim.v.lang or (vim.env.LC_ALL or vim.env.LC_MESSAGES or vim.env.LANG or "")
  return env:lower():match("^lt") and "lt" or "en"
end

--- A string with `{name}` placeholders filled in.
---@param key string
---@param params? table<string, any>
---@return string
--- The plural category of a whole number, by language (CLDR's rules for integers).
---@type table<string, fun(n: integer): "one"|"few"|"other">
M.plural = {
  en = function(n) return n == 1 and "one" or "other" end,
  -- 1, 21, 31 dienos; 2–9, 22 dienų; 0, 10–20, 30 dienų (the same word as few, a different rule)
  lt = function(n)
    local ten, hundred = n % 10, n % 100
    if hundred >= 11 and hundred <= 19 then return "other" end
    if ten == 1 then return "one" end
    if ten >= 2 then return "few" end
    return "other"
  end,
}

--- The template of a key in the current language: a plural message picks its form by
--- `params.count`.
---@param key string
---@param params? table<string, any>
---@return string
local function template(key, params)
  local language = M.language()
  local entry = M.catalogs[language][key] or en[key] or key
  if type(entry) == "table" then
    local count = params and tonumber(params.count) or 0
    entry = entry[M.plural[language](math.floor(math.abs(count)))] or entry.other
  end
  return entry
end

--- A string with `{name}` placeholders filled in.
---@param key string
---@param params? table<string, any>
---@return string
function M.t(key, params)
  local parts = {}
  for _, part in ipairs(M.parts(key, params)) do table.insert(parts, part.text) end
  return table.concat(parts)
end

--- A string in pieces: the message's own words, and the values put in its placeholders
--- (`value = true`), so a view can show the values brighter than the words around them.
---@param key string
---@param params? table<string, any>
---@return { text: string, value: boolean }[]
function M.parts(key, params)
  local text, parts, position = template(key, params), {}, 1
  while true do
    local from, to, name = text:find("{(%w+)}", position)
    local value = from and params and params[name]
    if not from then break end
    if from > position then table.insert(parts, { text = text:sub(position, from - 1), value = false }) end
    if value ~= nil then
      table.insert(parts, { text = tostring(value), value = true })
    else
      table.insert(parts, { text = text:sub(from, to), value = false })
    end
    position = to + 1
  end
  if position <= #text then table.insert(parts, { text = text:sub(position), value = false }) end
  return parts
end

--- A number with at most `decimals` decimals, none when whole, in the language's way:
--- "1.5" in English, "1,5" in Lithuanian, as the web formats them.
---@param value number
---@param decimals? integer
function M.number(value, decimals)
  local text = ("%." .. (decimals or 1) .. "f"):format(value)
  if text:find(".", 1, true) then text = text:gsub("0+$", ""):gsub("%.$", "") end
  return M.language() == "lt" and (text:gsub("%.", ",")) or text
end

--- The name of a month (1–12) as dates use it: "Dec", "gruodžio".
---@param month integer
function M.month(month)
  local months = M.catalogs[M.language()]["date.months"] or en["date.months"]
  return months[month]
end

return M
