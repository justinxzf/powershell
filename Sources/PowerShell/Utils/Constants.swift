import Foundation

enum Constants {
    static let knownCommands: Set<String> = [
        "ls", "cd", "pwd", "mkdir", "rm", "cp", "mv", "touch", "cat", "echo",
        "grep", "find", "sed", "awk", "sort", "uniq", "wc", "head", "tail",
        "chmod", "chown", "chgrp", "ln", "symlink", "tar", "gzip", "gunzip",
        "zip", "unzip", "curl", "wget", "ssh", "scp", "rsync", "ping",
        "ifconfig", "netstat", "lsof", "ps", "top", "kill", "killall",
        "df", "du", "free", "uptime", "whoami", "id", "su", "sudo",
        "apt", "brew", "npm", "yarn", "pnpm", "pip", "pip3", "conda",
        "gem", "cargo", "go", "rustc", "swift", "xcodebuild",
        "git", "docker", "kubectl", "helm", "terraform", "ansible",
        "make", "cmake", "gcc", "g++", "clang", "java", "javac",
        "python", "python3", "node", "ruby", "perl", "php",
        "vim", "nano", "less", "more", "man", "which", "whereis",
        "env", "export", "alias", "unalias", "source", "bash", "zsh",
        "sh", "fish", "open", "say", "defaults", "xattr", "launchctl",
        "tmux", "screen", "jq", "yq", "xargs", "tee", "diff", "patch",
        "base64", "md5", "shasum", "openssl", "ssh-keygen",
        "crontab", "at", "nohup", "disown", "trap", "wait",
        "test", "[", "[[", "true", "false", "return", "exit",
        "let", "expr", "bc", "date", "cal", "sleep", "time",
        "hexdump", "xxd", "strings", "file", "stat", "readlink",
        "dirname", "basename", "realpath", "mktemp", "install"
    ]

    static let dangerousPatterns: [String] = [
        "rm -rf /", "rm -rf /*", "rm -rf ~", "rm -rf ~/*",
        "mkfs", "dd if=", ":(){ :|:& };:",
        "> /dev/sda", "chmod -R 777 /",
        "wget.*| sh", "curl.*| sh"
    ]

    static let nlSentencePatterns: [String] = [
        "how to", "how do i", "how can i",
        "find all", "find every", "list all", "list every",
        "delete all", "delete every", "remove all", "remove every",
        "show me", "show all", "display all",
        "count all", "count the",
        "search for", "look for", "check if",
        "create a", "create an", "make a", "make an",
        "convert", "rename all",
        "what is", "what are", "which is",
        "where is", "where are",
        "sort by", "group by", "filter by"
    ]
}
