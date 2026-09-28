package com.example.server.utils;

import org.junit.jupiter.api.Test;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.File;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * Day3 最小单测：验证 OcrUtils 对真实 tesseract 命令的封装。
 *
 * <p>不依赖 Spring 容器（与 EvidenceVerificationServiceTest 同风格），
 * 用 java.awt 现画一张白底黑字图片，走真实 tesseract chi_sim+eng 识别，
 * 断言关键字符被识别出来。
 */
class OcrUtilsTest {

    private final OcrUtils ocrUtils = new OcrUtils("tesseract");

    @Test
    void recognizesTextFromRenderedImage() throws Exception {
        File image = File.createTempFile("dovideo-ocr-test-", ".png");
        try {
            BufferedImage img = new BufferedImage(900, 240, BufferedImage.TYPE_INT_RGB);
            Graphics2D g = img.createGraphics();
            g.setColor(Color.WHITE);
            g.fillRect(0, 0, 900, 240);
            g.setColor(Color.BLACK);
            g.setFont(new Font("Microsoft YaHei", Font.BOLD, 52));
            g.drawString("AI 视频分析 2026", 40, 90);
            g.drawString("OCR TEST 12345", 40, 180);
            g.dispose();
            ImageIO.write(img, "png", image);

            String text = ocrUtils.recognize(image);

            // 核心断言：数字与英文必须被识别出来（任何有 tesseract 的环境都成立）
            assertFalse(text.isBlank(), "OCR 结果不应为空");
            assertTrue(text.contains("12345"), "应识别出 12345，实际: " + text);
            assertTrue(text.contains("OCR"), "应识别出 OCR，实际: " + text);
            System.out.println("OCR result: " + text);
        } finally {
            //noinspection ResultOfMethodCallIgnored
            image.delete();
        }
    }

    @Test
    void rejectsMissingImageFile() {
        try {
            ocrUtils.recognize(new File("no-such-file.png"));
            throw new AssertionError("应当抛出 IllegalArgumentException");
        } catch (IllegalArgumentException expected) {
            // 预期行为：不存在的图片属于调用方参数错误，抛 IllegalArgumentException
        }
    }
}
