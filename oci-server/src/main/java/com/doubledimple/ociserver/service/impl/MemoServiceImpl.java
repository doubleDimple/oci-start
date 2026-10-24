package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.Memo;
import com.doubledimple.dao.repository.MemoRepository;
import com.doubledimple.ociserver.service.MemoService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;
import org.jsoup.nodes.Element;
import org.jsoup.safety.Cleaner;
import org.jsoup.safety.Safelist;

import javax.annotation.Resource;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Base64;
import java.util.List;

/**
 * @author doubleDimple
 * @date 2024:11:24日 12:42
 */
@Slf4j
@Service
public class MemoServiceImpl implements MemoService {

    private static final int TEXT_BYTES = 65535;
    private static final Safelist MEMO_HTML = new Safelist()
            .addTags("p", "br", "div", "h1", "h2", "h3", "strong", "b", "em", "i", "u", "s", "strike",
                    "blockquote", "pre", "code", "ul", "ol", "li", "a", "img")
            .addAttributes("a", "href", "title")
            .addAttributes("img", "src", "alt", "title")
            .addEnforcedAttribute("a", "target", "_blank")
            .addEnforcedAttribute("a", "rel", "noopener noreferrer");

    @Resource
    private MemoRepository memoRepository;

    @Override
    public List<Memo> getAllMemos() {
        return memoRepository.findAllByOrderByCreateTimeDesc();
    }

    @Override
    public Memo getMemoById(Long id) {
        requireId(id);
        return memoRepository.findById(id)
                .orElseThrow(() -> new MemoFailure("notFound"));
    }

    @Override
    @Transactional
    public Memo createMemo(Memo memo) {
        if (memo == null || memo.getId() != null) throw new MemoFailure("invalidInput");
        // Never merge client-supplied identities or timestamps into a stored note.
        return memoRepository.saveAndFlush(validatedContent(memo));
    }

    @Override
    @Transactional
    public Memo updateMemo(Long id, Memo memo) {
        return updateMemo(id, memo, null);
    }

    @Override
    @Transactional
    public Memo updateMemo(Long id, Memo memo, String expectedRevision) {
        requireId(id);
        if (memo == null || (memo.getId() != null && !id.equals(memo.getId()))) throw new MemoFailure("invalidInput");
        String expected = normalizeRevision(expectedRevision);
        Memo content = validatedContent(memo);
        Memo existingMemo = memoRepository.lockById(id).orElseThrow(() -> new MemoFailure("notFound"));
        checkRevision(existingMemo, expected);
        existingMemo.setTitle(content.getTitle());
        existingMemo.setContent(content.getContent());
        existingMemo.setSummary(content.getSummary());
        // Legacy text-only clients intentionally replace rich content with their new plain body.
        existingMemo.setHtmlContent(content.getHtmlContent());
        return memoRepository.saveAndFlush(existingMemo);
    }

    @Override
    @Transactional
    public void deleteMemo(Long id) {
        deleteMemo(id, null);
    }

    @Override
    @Transactional
    public void deleteMemo(Long id, String expectedRevision) {
        requireId(id);
        String expected = normalizeRevision(expectedRevision);
        Memo memo = memoRepository.lockById(id).orElseThrow(() -> new MemoFailure("notFound"));
        checkRevision(memo, expected);
        memoRepository.delete(memo);
        memoRepository.flush();
    }

    @Override
    public String getRevision(Memo memo) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            String[] fields = {String.valueOf(memo.getId()), memo.getTitle(), memo.getContent(), memo.getSummary(),
                    memo.getHtmlContent(), memo.getCreateTime() == null ? null : memo.getCreateTime().toString(),
                    memo.getUpdateTime() == null ? null : memo.getUpdateTime().toString()};
            for (String field : fields) {
                // Length framing distinguishes null/empty values and prevents concatenation ambiguities.
                if (field == null) {
                    digest.update("-1:".getBytes(StandardCharsets.UTF_8));
                } else {
                    byte[] bytes = field.getBytes(StandardCharsets.UTF_8);
                    digest.update((bytes.length + ":").getBytes(StandardCharsets.UTF_8));
                    digest.update(bytes);
                }
            }
            StringBuilder result = new StringBuilder(64);
            for (byte value : digest.digest()) {
                result.append(Character.forDigit((value >>> 4) & 15, 16));
                result.append(Character.forDigit(value & 15, 16));
            }
            return result.toString();
        } catch (Exception e) {
            throw new IllegalStateException("笔记版本读取失败");
        }
    }

    private void checkRevision(Memo memo, String expected) {
        if (expected != null && !expected.equals(getRevision(memo))) throw new MemoFailure("conflict");
    }

    private static String normalizeRevision(String value) {
        if (value == null) return null;
        if (value.length() == 66 && value.startsWith("\"") && value.endsWith("\"")) {
            value = value.substring(1, value.length() - 1);
        }
        if (!value.matches("[a-f0-9]{64}")) throw new MemoFailure("invalidInput");
        return value;
    }

    private static void requireId(Long id) {
        if (id == null || id <= 0) throw new MemoFailure("invalidInput");
    }

    private static Memo validatedContent(Memo input) {
        String title = input.getTitle() == null ? "" : input.getTitle().trim();
        String content = input.getContent();
        String summary = input.getSummary() == null ? "" : input.getSummary().trim();
        if (title.isEmpty() || title.length() > 255 || summary.length() > 200
                || content == null || content.trim().isEmpty()) throw new MemoFailure("invalidInput");
        requireTextSize(content);
        requireTextSize(summary);
        Memo result = new Memo();
        result.setTitle(title);
        result.setContent(content);
        result.setSummary(summary);
        result.setHtmlContent(sanitizeHtml(input.getHtmlContent()));
        return result;
    }

    private static void requireTextSize(String value) {
        if (value.getBytes(StandardCharsets.UTF_8).length > TEXT_BYTES) throw new MemoFailure("invalidInput");
    }

    private static String sanitizeHtml(String html) {
        if (html == null || html.trim().isEmpty()) return null;
        requireTextSize(html);
        Document cleaned = new Cleaner(MEMO_HTML).clean(Jsoup.parseBodyFragment(html));
        cleaned.outputSettings().prettyPrint(false);
        for (Element link : cleaned.select("a[href]")) {
            if (!safeUrl(link.attr("href"), false)) link.unwrap();
        }
        for (Element image : cleaned.select("img")) {
            if (!safeUrl(image.attr("src"), true)) image.remove();
        }
        String result = cleaned.body().html();
        requireTextSize(result);
        return result.trim().isEmpty() ? null : result;
    }

    private static boolean safeUrl(String value, boolean image) {
        if (value == null || value.isEmpty() || !value.equals(value.trim()) || value.indexOf('\\') >= 0) return false;
        for (int i = 0; i < value.length(); i++) if (Character.isISOControl(value.charAt(i))) return false;
        if (image && value.matches("(?i)data:image/(png|jpeg|gif|webp);base64,[a-z0-9+/]+={0,2}")) {
            try {
                byte[] bytes = Base64.getDecoder().decode(value.substring(value.indexOf(',') + 1));
                String type = value.substring("data:image/".length(), value.indexOf(';'));
                if ("png".equalsIgnoreCase(type)) {
                    return startsWith(bytes, new byte[]{(byte) 137, 80, 78, 71, 13, 10, 26, 10});
                }
                if ("jpeg".equalsIgnoreCase(type)) return startsWith(bytes, new byte[]{(byte) 255, (byte) 216, (byte) 255});
                if ("gif".equalsIgnoreCase(type)) {
                    return startsWith(bytes, "GIF87a".getBytes(StandardCharsets.US_ASCII))
                            || startsWith(bytes, "GIF89a".getBytes(StandardCharsets.US_ASCII));
                }
                return bytes.length >= 12 && startsWith(bytes, "RIFF".getBytes(StandardCharsets.US_ASCII))
                        && bytes[8] == 'W' && bytes[9] == 'E' && bytes[10] == 'B' && bytes[11] == 'P';
            } catch (IllegalArgumentException e) {
                return false;
            }
        }
        try {
            URI uri = new URI(value);
            if (!image && "mailto".equalsIgnoreCase(uri.getScheme())) {
                String address = uri.getSchemeSpecificPart();
                if (address == null || address.trim().isEmpty()) return false;
                for (int i = 0; i < address.length(); i++) if (Character.isISOControl(address.charAt(i))) return false;
                return true;
            }
            return ("http".equalsIgnoreCase(uri.getScheme()) || "https".equalsIgnoreCase(uri.getScheme()))
                    && uri.getHost() != null && uri.getRawUserInfo() == null
                    && (!image || uri.getRawFragment() == null)
                    && (uri.getPort() == -1 || (uri.getPort() >= 1 && uri.getPort() <= 65535));
        } catch (Exception e) {
            return false;
        }
    }

    private static boolean startsWith(byte[] value, byte[] prefix) {
        if (value.length < prefix.length) return false;
        for (int i = 0; i < prefix.length; i++) if (value[i] != prefix[i]) return false;
        return true;
    }
}
