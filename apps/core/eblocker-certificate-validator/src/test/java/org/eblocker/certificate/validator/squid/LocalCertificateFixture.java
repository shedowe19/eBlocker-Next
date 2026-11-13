// SPDX-License-Identifier: EUPL-1.2
package org.eblocker.certificate.validator.squid;

import com.sun.net.httpserver.HttpServer;
import org.bouncycastle.asn1.x500.X500Name;
import org.bouncycastle.asn1.x509.*;
import org.bouncycastle.cert.X509v2CRLBuilder;
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter;
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder;
import org.bouncycastle.openssl.jcajce.JcaPEMWriter;
import org.bouncycastle.operator.ContentSigner;
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder;

import java.io.IOException;
import java.io.StringWriter;
import java.math.BigInteger;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.cert.X509Certificate;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.Date;
import java.util.concurrent.atomic.AtomicInteger;

/** Ephemeral test-only CA and signed revocation data; no external PKI or saved private keys. */
final class LocalCertificateFixture implements AutoCloseable {
    final Path caFile;
    final X509Certificate valid;
    final X509Certificate revoked;
    final X509Certificate expired;
    final X509Certificate root;
    final AtomicInteger crlRequests = new AtomicInteger();
    private final HttpServer server;
    private final Path directory;
    private final KeyPair caKey;
    private final X500Name issuer = new X500Name("CN=eBlocker ephemeral test CA");
    private final Instant now = Instant.now();
    private final String crlUrl;

    LocalCertificateFixture() throws Exception {
        directory = Files.createTempDirectory("eblocker-test-pki-");
        caFile = directory.resolve("ca.pem");
        server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        crlUrl = "http://127.0.0.1:" + server.getAddress().getPort() + "/test.crl";
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(2048);
        caKey = generator.generateKeyPair();
        root = certificate(BigInteger.ONE, caKey, issuer, true, now.plus(7, ChronoUnit.DAYS));
        KeyPair leafKey = generator.generateKeyPair();
        valid = certificate(BigInteger.valueOf(2), leafKey, new X500Name("CN=fixture.test"), false, now.plus(1, ChronoUnit.DAYS));
        revoked = certificate(BigInteger.valueOf(3), leafKey, new X500Name("CN=fixture.test"), false, now.plus(1, ChronoUnit.DAYS));
        expired = certificate(BigInteger.valueOf(4), leafKey, new X500Name("CN=fixture.test"), false, now.minus(1, ChronoUnit.HOURS));
        X509v2CRLBuilder builder = new X509v2CRLBuilder(issuer, Date.from(now.minus(1, ChronoUnit.HOURS)));
        builder.setNextUpdate(Date.from(now.plus(1, ChronoUnit.DAYS)));
        builder.addCRLEntry(revoked.getSerialNumber(), Date.from(now.minus(30, ChronoUnit.MINUTES)), CRLReason.keyCompromise);
        byte[] crl = builder.build(signer()).getEncoded();
        server.createContext("/test.crl", exchange -> {
            crlRequests.incrementAndGet();
            exchange.getResponseHeaders().set("Content-Type", "application/pkix-crl");
            exchange.sendResponseHeaders(200, crl.length);
            try (java.io.OutputStream out = exchange.getResponseBody()) { out.write(crl); }
        });
        try (StringWriter text = new StringWriter(); JcaPEMWriter writer = new JcaPEMWriter(text)) {
            writer.writeObject(root); writer.flush();
            Files.write(caFile, text.toString().getBytes(StandardCharsets.US_ASCII));
        }
        server.start();
    }

    private ContentSigner signer() throws Exception {
        return new JcaContentSignerBuilder("SHA256withRSA").build(caKey.getPrivate());
    }

    private X509Certificate certificate(BigInteger serial, KeyPair key, X500Name subject, boolean ca, Instant expiry) throws Exception {
        JcaX509v3CertificateBuilder builder = new JcaX509v3CertificateBuilder(issuer, serial,
                Date.from(now.minus(1, ChronoUnit.DAYS)), Date.from(expiry), subject, key.getPublic());
        builder.addExtension(Extension.basicConstraints, true, new BasicConstraints(ca));
        builder.addExtension(Extension.keyUsage, true, new KeyUsage(ca ? KeyUsage.keyCertSign | KeyUsage.cRLSign : KeyUsage.digitalSignature | KeyUsage.keyEncipherment));
        if (!ca) {
            DistributionPointName name = new DistributionPointName(new GeneralNames(new GeneralName(GeneralName.uniformResourceIdentifier, crlUrl)));
            builder.addExtension(Extension.cRLDistributionPoints, false, new CRLDistPoint(new DistributionPoint[]{new DistributionPoint(name, null, null)}));
            builder.addExtension(Extension.subjectAlternativeName, false, new GeneralNames(new GeneralName(GeneralName.dNSName, "fixture.test")));
        }
        return new JcaX509CertificateConverter().getCertificate(builder.build(signer()));
    }

    CertificateValidationRequest request(X509Certificate leaf, boolean concurrent) {
        return new CertificateValidationRequest(concurrent ? 1L : null, null, null, "fixture.test",
                new X509Certificate[]{leaf, root}, null, null, concurrent);
    }

    @Override public void close() throws IOException {
        server.stop(0);
        Files.deleteIfExists(caFile);
        Files.deleteIfExists(directory.resolve("crl.cache"));
        Files.deleteIfExists(directory);
    }
}
