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

import org.eblocker.certificate.validator.http.DefaultHttpUrlConnectionBuilderFactory;
import org.eblocker.crypto.CryptoException;
import org.junit.jupiter.api.AfterAll;
import org.junit.jupiter.api.Assertions;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.security.InvalidAlgorithmParameterException;
import java.security.NoSuchAlgorithmException;
import java.security.Security;
import java.security.cert.CertStore;
import java.time.Clock;

class SunCertificateValidatorTest {

    private final boolean useConcurrency = true;
    private SunCertificateValidator certificateValidator;
    private static LocalCertificateFixture fixture;

    @BeforeAll
    static void beforeClass() throws Exception {
        fixture = new LocalCertificateFixture();
        Security.addProvider(new CertificateValidatorProvider());
    }

    @AfterAll
    static void afterClass() throws Exception {
        fixture.close();
        Security.removeProvider("eBlockerCertificateValidator");
    }

    @BeforeEach
    void setup() throws InvalidAlgorithmParameterException, NoSuchAlgorithmException {
        CrlCache crlCache = new CrlCache(16, 1, 65536, Clock.systemUTC(), new DefaultHttpUrlConnectionBuilderFactory());
        CertStore certStore = CertStore.getInstance("crlCacheStore", new CrlCacheCertStore.Parameters(crlCache));
        certificateValidator = new SunCertificateValidator(fixture.caFile, true, certStore, null, null);
    }

    @Test
    void test_ok() throws IOException, CryptoException {
        CertificateValidationRequest request = fixture.request(fixture.valid, useConcurrency);
        CertificateValidationResponse response = certificateValidator.validate(request, useConcurrency);
        Assertions.assertEquals("OK", response.getMessage());
        Assertions.assertTrue(fixture.crlRequests.get() > 0, "Signed local revocation data must be checked");
    }

    @Test
    void test_untrusted() throws Exception {
        try (LocalCertificateFixture untrusted = new LocalCertificateFixture()) {
            CertificateValidationResponse response = certificateValidator.validate(untrusted.request(untrusted.valid, useConcurrency), useConcurrency);
            Assertions.assertEquals("ERR", response.getMessage());
        }
    }

    @Test
    void test_invalid() throws IOException, CryptoException {
        CertificateValidationRequest request = fixture.request(fixture.expired, useConcurrency);
        CertificateValidationResponse response = certificateValidator.validate(request, useConcurrency);
        Assertions.assertEquals("ERR", response.getMessage());
    }

    @Test
    void test_revoked() throws IOException, CryptoException {
        CertificateValidationRequest request = fixture.request(fixture.revoked, useConcurrency);
        CertificateValidationResponse response = certificateValidator.validate(request, useConcurrency);
        Assertions.assertEquals("ERR", response.getMessage());
    }
}
