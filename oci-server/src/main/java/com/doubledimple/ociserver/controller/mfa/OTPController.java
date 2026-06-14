package com.doubledimple.ociserver.controller.mfa;

import cn.hutool.core.util.StrUtil;
import com.doubledimple.dao.entity.OTPKey;
import com.doubledimple.dao.repository.OTPKeyRepository;
import com.doubledimple.ociserver.controller.BaseController;
import com.doubledimple.ociserver.pojo.request.OtpBatchRequest;
import com.doubledimple.ociserver.pojo.response.OtpResponse;
import com.doubledimple.ociserver.pojo.response.OtpResponse2;
import com.doubledimple.ociserver.service.mfa.OTPService;
import com.doubledimple.ociserver.service.mfa.QRCodeService;
import com.doubledimple.ociserver.utils.google.GoogleAuthMigrationParser;
import com.google.zxing.BinaryBitmap;
import com.google.zxing.MultiFormatReader;
import com.google.zxing.Result;
import com.google.zxing.WriterException;
import com.google.zxing.client.j2se.BufferedImageLuminanceSource;
import com.google.zxing.common.HybridBinarizer;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import com.doubledimple.ociserver.config.context.UserContext;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.multipart.MultipartFile;

import javax.annotation.Resource;
import javax.imageio.ImageIO;
import javax.servlet.http.HttpServletResponse;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.io.PrintWriter;
import java.net.URI;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicReference;


/**
 * @author doubleDimple
 * @date 2024:10:05日 01:00
 */
@Controller
@Slf4j
public class OTPController  extends BaseController {

    @Resource
    private OTPService otpService;

    @Resource
    private QRCodeService qrCodeService;

    @Resource
    private OTPKeyRepository otpKeyRepository;

    // 显示主页（PC）
    @GetMapping("/mfa/page")
    public String mfa(Model model) throws IOException, WriterException {
        List<OTPKey> otpKeys = otpService.getAllKeys();
        if (otpKeys.size() > 0){
            model.addAttribute("otpKeys", otpKeys);
        }
        model.addAttribute("activePage", "api-mfa");
        return "mfa";
    }

    // 移动端 MFA 页面
    @GetMapping("/m/mfa")
    public String mobileMfa(Model model) {
        List<OTPKey> otpKeys = otpService.getAllKeys();
        if (otpKeys != null && !otpKeys.isEmpty()) {
            model.addAttribute("otpKeys", otpKeys);
        }
        model.addAttribute("activePage", "mfa");
        model.addAttribute("currentUsername", UserContext.getUsername());
        return "mobile/mfa";
    }

    // 保存密钥
    @PostMapping("/save-secret")
    public String saveSecret(@RequestParam(value ="keyName", required = false) String keyName,
                             @RequestParam(value ="secretKey", required = false) String secretKey,
                             @RequestParam(value = "qrCode", required = false) MultipartFile qrCode,
                             @RequestParam(value = "qrUrl", required = false) String qrUrl) {
        if (StringUtils.isNotBlank(secretKey))secretKey = StrUtil.trim(secretKey);
        AtomicReference<String> finalSecretKey = new AtomicReference<>(secretKey);
        List<Map<String, String>> accounts = new ArrayList<>();
        if(StringUtils.isEmpty(keyName)){
            keyName = System.currentTimeMillis()+"";
        }
        try {
        // 摄像头扫码直接传入 URL 文本（otpauth:// 或 otpauth-migration://）
        if (StringUtils.isNotBlank(qrUrl)) {
            String url = qrUrl.trim();
            log.info("qrUrl text is: {}", url);
            if (url.startsWith("otpauth-migration://")) {
                List<GoogleAuthMigrationParser.OtpParameters> otpParameters = GoogleAuthMigrationParser.parseUri(url);
                List<OTPKey> otpKeys = new ArrayList<>();
                for (GoogleAuthMigrationParser.OtpParameters account : otpParameters) {
                    OTPKey otpKey = new OTPKey();
                    otpKey.setKeyName(account.getName());
                    otpKey.setSecretKey(account.getSecretInBase32());
                    otpKey.setIssuer(account.getIssuer() != null ? account.getIssuer() : "mfa-start");
                    String otpAuthUri = String.format("otpauth://totp/%s:%s?secret=%s&issuer=%s",
                            otpKey.getIssuer(), otpKey.getKeyName(), otpKey.getSecretKey(), otpKey.getIssuer());
                    otpKey.setQrCode(qrCodeService.generateQRCodeImage(otpAuthUri));
                    OTPKey existing = otpKeyRepository.findBySecretKey(otpKey.getSecretKey());
                    otpKeys.add(existing != null ? existing : otpKey);
                }
                otpService.saveListKey(otpKeys);
            } else if (url.startsWith("otpauth://")) {
                URI uri = new URI(url);
                String query = uri.getQuery();
                Arrays.stream(query.split("&"))
                        .filter(param -> param.startsWith("secret="))
                        .findFirst()
                        .ifPresent(secret -> finalSecretKey.set(secret.substring(7)));
                if (finalSecretKey.get() == null || finalSecretKey.get().trim().isEmpty()) {
                    throw new IllegalArgumentException("Secret key is required");
                }
                OTPKey otpKey = new OTPKey(keyName, finalSecretKey.get());
                otpKey.setIssuer("mfa-start");
                if (otpKeyRepository.findBySecretKey(otpKey.getSecretKey()) == null) {
                    otpService.saveKey(otpKey);
                }
            }
        // 如果上传了二维码文件，则解析二维码
        } else if (qrCode != null && !qrCode.isEmpty()) {
            // 读取图片
            BufferedImage image = ImageIO.read(qrCode.getInputStream());
            if (image == null) {
                throw new IllegalArgumentException("Invalid image file");
            }

            // 使用ZXing解析二维码
            BinaryBitmap binaryBitmap = new BinaryBitmap(new HybridBinarizer(
                    new BufferedImageLuminanceSource(image)));
            Result result = new MultiFormatReader().decode(binaryBitmap);

            // 解析 otpauth:// URI
            String qrContent = result.getText();
            log.info("qrCode text is: {}",qrContent);
            if (qrContent.startsWith("otpauth://")) {
                URI uri = new URI(qrContent);
                String query = uri.getQuery();
                // 从查询参数中获取 secret
                Arrays.stream(query.split("&"))
                        .filter(param -> param.startsWith("secret="))
                        .findFirst()
                        .ifPresent(secret -> {
                            finalSecretKey.set(secret.substring(7));// 去掉 "secret=" 前缀
                        });
                // 验证 secretKey 不为空
                if (finalSecretKey.get() == null || finalSecretKey.get().trim().isEmpty()) {
                    throw new IllegalArgumentException("Secret key is required");
                }
                OTPKey otpKey = new OTPKey(keyName, finalSecretKey.get());
                otpKey.setIssuer("mfa-start");
                OTPKey byKeyName = otpKeyRepository.findBySecretKey(otpKey.getSecretKey());
                if (byKeyName == null){
                    otpService.saveKey(otpKey);
                }

            } else if (qrContent.startsWith("otpauth-migration://")) {

                List<GoogleAuthMigrationParser.OtpParameters> otpParameters = GoogleAuthMigrationParser.parseUri(qrContent);
                List<OTPKey> otpKeys = new ArrayList<>();
                for (GoogleAuthMigrationParser.OtpParameters account : otpParameters) {
                    OTPKey otpKey = new OTPKey();
                    otpKey.setKeyName(account.getName());
                    otpKey.setSecretKey(account.getSecretInBase32());
                    if (account.getIssuer() == null){
                        otpKey.setIssuer("mfa-start");
                    }else {
                        otpKey.setIssuer(account.getIssuer());
                    }
                    String otpAuthUri = String.format("otpauth://totp/%s:%s?secret=%s&issuer=%s",
                            otpKey.getIssuer(), otpKey.getKeyName(), otpKey.getSecretKey(), otpKey.getIssuer());

                    String qrCodeNew = qrCodeService.generateQRCodeImage(otpAuthUri);
                    otpKey.setQrCode(qrCodeNew);
                    OTPKey byKeyName = otpKeyRepository.findBySecretKey(otpKey.getSecretKey());
                    if (byKeyName != null){
                        otpKeys.add(byKeyName);
                    }else {
                        otpKeys.add(otpKey);
                    }

                }
                otpService.saveListKey(otpKeys);
            }
        }else {
            OTPKey otpKey = new OTPKey(keyName, secretKey);
            otpKey.setIssuer("mfa-start");
            OTPKey byKeyName = otpKeyRepository.findByKeyName(keyName);
            if (byKeyName == null){
                otpService.saveKey(new OTPKey(keyName,secretKey));
            }
        }
        log.info("result:{}",accounts);
        return "redirect:/mfa/page";
    } catch (Exception e) {
        log.error("保存秘钥出现异常");
        return "redirect:/mfa/page";
    }
    }

    // 生成 OTP 码
    @GetMapping("/generate-otp")
    @ResponseBody
    public OtpResponse2 generateOtp(@RequestParam("secretKey") String secretKey) {
        String otpCode = otpService.generateOtpCode(secretKey);
        return new OtpResponse2(otpCode);
    }

    // 生成 OTP 码
    @PostMapping("/generate-otp-batch")
    public ResponseEntity<List<OtpResponse>> generateOtpBatch(@RequestBody OtpBatchRequest request) {
        try {
            List<OtpResponse> otpResponses = otpService.generateOtpBatch(request.getSecretKeys());
            return ResponseEntity.ok(otpResponses);
        } catch (Exception e) {
            log.error("Error generating OTP batch", e);
            return ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).build();
        }
    }

    @PostMapping("/delete-key")
    @ResponseBody
    public OtpResponse2 deleteKey(@RequestBody Map<String, String> payload) {
        String keyName = payload.get("keyName");
        if (keyName == null || keyName.isEmpty()) {
            return new OtpResponse2("keyName is null");
        }
        otpService.deleteKey(keyName);
        return new OtpResponse2("OK");
    }


    @GetMapping("/export-data")
    public void exportToCSV(HttpServletResponse response) throws IOException {
        response.setContentType("text/csv");
        response.setHeader("Content-Disposition", "attachment; filename=\"otp_keys.csv\"");
        PrintWriter writer = response.getWriter();
        writer.println("Key Name,Issuer,Secret Key,Created Date");

        List<OTPKey> otpKeys = otpService.getAllKeys();
        for (OTPKey otpKey : otpKeys) {
            writer.printf("%s,%s,%s,%s%n", otpKey.getKeyName(), otpKey.getIssuer(), otpKey.getSecretKey(),otpKey.getCreateTime());
        }
        writer.flush();
    }
}
