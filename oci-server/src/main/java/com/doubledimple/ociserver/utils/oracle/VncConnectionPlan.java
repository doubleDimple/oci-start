package com.doubledimple.ociserver.utils.oracle;

import java.io.IOException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * A validated routing plan from OCI's VNC connection string, never an executable
 * shell command. The caller supplies its own key and host-verification options.
 * Serial console strings without an explicit local forwarding are rejected.
 */
public final class VncConnectionPlan {
    private static final int MAX_COMMAND_LENGTH = 32768;
    private static final int MAX_TOKENS = 128;
    private static final String LOCAL_BIND = "127.0.0.1";

    private final String outerHost;
    private final String outerUser;
    private final int outerPort;
    private final String proxyHost;
    private final String proxyUser;
    private final int proxyPort;
    private final String forwardHost;
    private final int forwardPort;

    private VncConnectionPlan(SshCommand outer, SshCommand proxy, Forward forward) {
        this.outerHost = outer.host;
        this.outerUser = outer.user;
        this.outerPort = outer.port;
        this.proxyHost = proxy == null ? null : proxy.host;
        this.proxyUser = proxy == null ? null : proxy.user;
        this.proxyPort = proxy == null ? 0 : proxy.port;
        this.forwardHost = forward.host;
        this.forwardPort = forward.port;
    }

    public String getOuterHost() { return outerHost; }
    public String getOuterUser() { return outerUser; }
    public int getOuterPort() { return outerPort; }
    public String getProxyHost() { return proxyHost; }
    public String getProxyUser() { return proxyUser; }
    /** Returns zero only when there is no proxy hop. */
    public int getProxyPort() { return proxyPort; }
    public String getForwardHost() { return forwardHost; }
    public int getForwardPort() { return forwardPort; }
    public String getLocalBind() { return LOCAL_BIND; }

    /** The cloud command's local listener is always replaced by our reservation. */
    public String localForward(int reservedPort) throws IOException {
        if (reservedPort < 1 || reservedPort > 65535) throw invalid();
        return LOCAL_BIND + ":" + reservedPort + ":" + forwardHost + ":" + forwardPort;
    }

    public static VncConnectionPlan parse(String raw, String expectedInstanceId,
                                          String expectedConnectionId) throws IOException {
        if (!ocid(expectedInstanceId, "instance")
                || !ocid(expectedConnectionId, "instanceconsoleconnection")) throw invalid();
        SshCommand outer = parseSsh(raw, false);
        if (outer.forward == null) throw invalid();
        Forward forward = parseForward(outer.forward);
        SshCommand proxy = outer.proxyCommand == null ? null : parseSsh(outer.proxyCommand, true);

        if (proxy == null) {
            // Direct console-service tunnel: the forwarding names the instance.
            if (!consoleHost(outer.host) || !expectedConnectionId.equals(outer.user)
                    || !expectedInstanceId.equals(forward.host)) throw invalid();
            outer.host = outer.host.toLowerCase(Locale.ROOT);
        } else {
            // The service hop authenticates the connection and forwards to the
            // exact instance named by the outer hop. Do not guess any port.
            if (!consoleHost(proxy.host) || !expectedConnectionId.equals(proxy.user)
                    || !expectedInstanceId.equals(outer.host)
                    || (outer.user != null && !expectedInstanceId.equals(outer.user)
                        && !expectedConnectionId.equals(outer.user))) throw invalid();
            if (!expectedInstanceId.equals(forward.host) && !"localhost".equals(forward.host)
                    && !LOCAL_BIND.equals(forward.host)) throw invalid();
            proxy.host = proxy.host.toLowerCase(Locale.ROOT);
        }
        return new VncConnectionPlan(outer, proxy, forward);
    }

    private static SshCommand parseSsh(String raw, boolean proxyHop) throws IOException {
        List<String> tokens = tokenize(raw);
        if (tokens.size() < 2 || !"ssh".equals(tokens.get(0))) throw invalid();
        SshCommand result = new SshCommand();
        boolean hasPort = false;
        boolean hasUser = false;
        Set<String> options = new HashSet<>();
        for (int i = 1; i < tokens.size(); i++) {
            String token = tokens.get(i);
            if ("--".equals(token)) {
                if (++i != tokens.size() - 1) throw invalid();
                readDestination(result, tokens.get(i), hasUser);
                break;
            }
            if (!token.startsWith("-")) {
                // No remote command, post-destination options, or extra hosts.
                if (i != tokens.size() - 1) throw invalid();
                readDestination(result, token, hasUser);
                break;
            }
            if (token.matches("-[NT]+")) continue;
            if (token.length() < 2) throw invalid();
            char option = token.charAt(1);
            if (option != 'p' && option != 'l' && option != 'L' && option != 'o' && option != 'W') {
                throw invalid();
            }
            String value;
            if (token.length() == 2) {
                if (++i >= tokens.size()) throw invalid();
                value = tokens.get(i);
            } else {
                value = token.substring(2);
            }
            if (value.isEmpty()) throw invalid();
            switch (option) {
                case 'p':
                    if (hasPort) throw invalid();
                    result.port = port(value);
                    hasPort = true;
                    break;
                case 'l':
                    if (hasUser || !identifier(value)) throw invalid();
                    result.user = value;
                    hasUser = true;
                    break;
                case 'L':
                    if (proxyHop || result.forward != null) throw invalid();
                    result.forward = value;
                    break;
                case 'W':
                    if (!proxyHop || result.stdioForward || !"%h:%p".equals(value)) throw invalid();
                    result.stdioForward = true;
                    break;
                case 'o':
                    readOption(result, value, proxyHop, options);
                    break;
                default:
                    throw invalid();
            }
        }
        if (result.host == null || (proxyHop && !result.stdioForward)) throw invalid();
        return result;
    }

    private static void readDestination(SshCommand command, String destination,
                                        boolean hasUser) throws IOException {
        int at = destination.indexOf('@');
        if (at >= 0) {
            if (hasUser || at == 0 || at != destination.lastIndexOf('@')) throw invalid();
            command.user = destination.substring(0, at);
            destination = destination.substring(at + 1);
            if (!identifier(command.user)) throw invalid();
        }
        if (!identifier(destination)) throw invalid();
        command.host = destination;
    }

    private static void readOption(SshCommand command, String raw, boolean proxyHop,
                                   Set<String> options) throws IOException {
        int separator = 0;
        while (separator < raw.length() && raw.charAt(separator) != '='
                && raw.charAt(separator) != ' ' && raw.charAt(separator) != '\t') separator++;
        if (separator == 0 || separator == raw.length()) throw invalid();
        String name = raw.substring(0, separator).toLowerCase(Locale.ROOT);
        String value = raw.substring(separator).trim();
        if (value.startsWith("=")) value = value.substring(1).trim();
        if (value.isEmpty() || !options.add(name)) throw invalid();
        if ("proxycommand".equals(name)) {
            if (proxyHop || command.proxyCommand != null) throw invalid();
            command.proxyCommand = value;
            return;
        }
        // These values never reach ProcessBuilder. Our builder supplies the
        // key, trust store, non-interactive mode, and forwarding-failure policy.
        switch (name) {
            case "stricthostkeychecking":
            case "userknownhostsfile":
            case "globalknownhostsfile":
            case "hostkeyalias":
            case "hostkeyalgorithms":
            case "pubkeyacceptedkeytypes":
            case "pubkeyacceptedalgorithms":
            case "updatehostkeys":
            case "checkhostip":
            case "verifyhostkeydns":
            case "batchmode":
            case "exitonforwardfailure":
                return;
            default:
                throw invalid();
        }
    }

    private static Forward parseForward(String raw) throws IOException {
        String[] fields = raw.split(":", -1);
        int offset;
        if (fields.length == 3) {
            offset = 0;
        } else if (fields.length == 4) {
            String bind = fields[0];
            if (!bind.isEmpty() && !"*".equals(bind) && !"localhost".equals(bind)
                    && !LOCAL_BIND.equals(bind) && !"0.0.0.0".equals(bind)) throw invalid();
            offset = 1;
        } else {
            // UNIX sockets and ambiguous/unbracketed IPv6 forwardings are not
            // part of the supported console route grammar.
            throw invalid();
        }
        port(fields[offset]); // Validate even though the local port is replaced.
        String host = fields[offset + 1];
        if (!identifier(host)) throw invalid();
        return new Forward(host, port(fields[offset + 2]));
    }

    /** Bounded shell-style lexical splitting only; no substitutions or execution. */
    private static List<String> tokenize(String raw) throws IOException {
        if (raw == null || raw.isEmpty() || raw.length() > MAX_COMMAND_LENGTH) throw invalid();
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            if ((Character.isISOControl(c) && c != '\t') || c == '$' || c == '`'
                    || c == ';' || c == '|' || c == '&' || c == '<' || c == '>') throw invalid();
        }
        List<String> tokens = new ArrayList<>();
        StringBuilder token = new StringBuilder();
        char quote = 0;
        boolean started = false;
        for (int i = 0; i < raw.length(); i++) {
            char c = raw.charAt(i);
            if (quote == '\'') {
                if (c == '\'') quote = 0;
                else token.append(c);
            } else if (quote == '"') {
                if (c == '"') {
                    quote = 0;
                } else if (c == '\\') {
                    if (i + 1 >= raw.length()) throw invalid();
                    char next = raw.charAt(i + 1);
                    if (next == '"' || next == '\\') { token.append(next); i++; }
                    else token.append(c);
                } else {
                    token.append(c);
                }
            } else if (c == ' ' || c == '\t') {
                if (started) {
                    addToken(tokens, token);
                    started = false;
                }
            } else {
                started = true;
                if (c == '\'' || c == '"') {
                    quote = c;
                } else if (c == '\\') {
                    if (++i >= raw.length()) throw invalid();
                    token.append(raw.charAt(i));
                } else {
                    token.append(c);
                }
            }
        }
        if (quote != 0) throw invalid();
        if (started) addToken(tokens, token);
        return tokens;
    }

    private static void addToken(List<String> tokens, StringBuilder token) throws IOException {
        if (tokens.size() >= MAX_TOKENS) throw invalid();
        tokens.add(token.toString());
        token.setLength(0);
    }

    private static int port(String raw) throws IOException {
        if (!raw.matches("[0-9]{1,5}")) throw invalid();
        int value = Integer.parseInt(raw);
        if (value < 1 || value > 65535) throw invalid();
        return value;
    }

    private static boolean identifier(String value) {
        return value != null && value.length() <= 512 && value.matches("[A-Za-z0-9][A-Za-z0-9._-]*");
    }

    private static boolean ocid(String value, String type) {
        return identifier(value) && value.startsWith("ocid1." + type + ".")
                && value.length() > ("ocid1." + type + ".").length();
    }

    private static boolean consoleHost(String host) {
        return host != null && host.length() <= 253 && host.toLowerCase(Locale.ROOT)
                .matches("instance-console\\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.oci\\.oraclecloud\\.com");
    }

    private static IOException invalid() {
        return new IOException("OCI VNC 连接字符串格式不受支持或与当前实例不匹配");
    }

    private static final class SshCommand {
        private String host;
        private String user;
        private int port = 22; // OpenSSH default, never a guessed VNC port.
        private String forward;
        private String proxyCommand;
        private boolean stdioForward;
    }

    private static final class Forward {
        private final String host;
        private final int port;
        private Forward(String host, int port) { this.host = host; this.port = port; }
    }
}
