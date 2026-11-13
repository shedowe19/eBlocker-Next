/*
 * Copyright 2020 eBlocker Open Source UG (haftungsbeschraenkt)
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be
 * approved by the European Commission - subsequent versions of the EUPL
 * (the "License"); You may not use this work except in compliance with
 * the License. You may obtain a copy of the License at:
 *
 *   https://joinup.ec.europa.eu/page/eupl-text-11-12
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */
package org.eblocker.certificate.validator.squid;

import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.AfterAll;
import java.security.Security;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.io.PipedInputStream;
import java.io.PipedOutputStream;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

@org.junit.jupiter.api.Timeout(10)
class CertificateValidatorAppTest {
    private static final Logger LOG = LoggerFactory.getLogger(CertificateValidatorAppTest.class);

    private static final boolean useConcurrency = false;
    private static LocalCertificateFixture fixture;
    private static CertificateValidatorApp app;
    private static final PipedOutputStream stdinWriter = new PipedOutputStream();
    private static final PipedInputStream stdoutReader = new PipedInputStream();

    private static CertificateValidationResponseReader responseReader = new CertificateValidationResponseReader(useConcurrency);

    @BeforeAll
    static void setUp() throws Exception {
        fixture = new LocalCertificateFixture();
        Security.addProvider(new CertificateValidatorProvider());
        //
        // Create piped streams as replacement for STDIN and STDOUT
        //
        final PipedInputStream stdinReader = new PipedInputStream(stdinWriter);
        final PipedOutputStream stdoutWriter = new PipedOutputStream(stdoutReader);

        Properties properties = TestProperties.createTestProperties(useConcurrency);
        properties.setProperty("validator.sun.certificates.path", fixture.caFile.toString());
        properties.setProperty("validator.sun.preferCrls", "true");
        properties.setProperty("cache.crl.enabled", "true");
        properties.setProperty("cache.crl.file", fixture.caFile.resolveSibling("crl.cache").toString());
        app = new CertificateValidatorApp(properties);
        app.serve(stdinReader, stdoutWriter);

    }

    @Test
    void testAlternatingRequests() throws Exception {
        //
        // Submit some (sequential) certificate validation requests
        //
        for (int i = 0; i < 10; i++) {
            if (i % 2 == 0) {
                checkValidCert();
            } else {
                checkInvalidCert();
            }
        }
    }

    @AfterAll
    static void tearDown() throws Exception {
        stdinWriter.close();
        stdoutReader.close();
        app.close();
        fixture.close();
        Security.removeProvider("eBlockerCertificateValidator");
    }

    @Test
    void testRevokedCert() throws Exception {
        submitRequest(fixture.request(fixture.revoked, useConcurrency), false);
    }

    @Test
    void testCertError() throws Exception {
        checkInvalidCertWithErrors();
    }

    private void checkValidCert() throws Exception {
        CertificateValidationRequest request = fixture.request(fixture.valid, useConcurrency);
        submitRequest(request, true);
        Assertions.assertTrue(fixture.crlRequests.get() > 0, "App must fetch signed revocation data");
    }

    private void checkInvalidCert() throws Exception {
        CertificateValidationRequest request = fixture.request(fixture.expired, useConcurrency);
        submitRequest(request, false);
    }

    private void checkInvalidCertWithErrors() throws Exception {
        CertificateValidationRequest valid = fixture.request(fixture.valid, useConcurrency);
        CertificateValidationRequest request = new CertificateValidationRequest(null, null, null, valid.getHost(), valid.getCert(),
                new String[]{"SQUID_X509_V_ERR_DOMAIN_MISMATCH"}, new String[]{"cert_0"}, useConcurrency);
        submitRequest(request, false);
    }

    private void submitRequest(CertificateValidationRequest request, boolean valid) throws IOException {
        stdinWriter.write(request.toString().getBytes(StandardCharsets.UTF_8));
        stdinWriter.write('\n');
        stdinWriter.flush();

        LOG.info("Reading response...");
        CertificateValidationResponse response = responseReader.readSquidFormat(stdoutReader);
        LOG.info("Response arrived");
        Assertions.assertNotNull(response);
        Assertions.assertEquals(valid, response.isSuccess());

    }

}
