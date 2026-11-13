package org.eblocker.certificate.validator.squid;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Properties;
import static org.junit.jupiter.api.Assertions.*;

class PropertyLoadingTest {
    @TempDir Path directory;

    private static class TrackedInput extends ByteArrayInputStream {
        boolean closed;
        TrackedInput(String text) { super(text.getBytes(StandardCharsets.ISO_8859_1)); }
        @Override public void close() throws IOException { closed = true; super.close(); }
    }

    @Test void defaultsRemainWhenOverrideMissing() throws IOException {
        TrackedInput input = new TrackedInput("local.propertiesPath=" + directory.resolve("absent") + "\na=default\n");
        assertEquals("default", CertificateValidatorApp.loadProperties(input).getProperty("a"));
        assertTrue(input.closed);
    }

    @Test void overridePreservesUnspecifiedDefaults() throws IOException {
        Path overrides = directory.resolve("local.properties");
        Files.write(overrides, "a=local\n".getBytes(StandardCharsets.ISO_8859_1));
        TrackedInput input = new TrackedInput("local.propertiesPath=" + overrides + "\na=default\nb=fallback\n");
        Properties properties = CertificateValidatorApp.loadProperties(input);
        assertEquals("local", properties.getProperty("a"));
        assertEquals("fallback", properties.getProperty("b"));
        assertTrue(input.closed);
    }

    @Test void closesDefaultStreamOnMalformedConfiguration() {
        TrackedInput input = new TrackedInput("bad=\\uXXXX");
        assertThrows(IllegalArgumentException.class, () -> CertificateValidatorApp.loadProperties(input));
        assertTrue(input.closed);
    }

    @Test void missingDefaultsProduceUsefulError() {
        assertThrows(IOException.class, () -> CertificateValidatorApp.loadProperties(null));
    }
}
