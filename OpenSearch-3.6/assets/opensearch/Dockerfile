ARG OPEN_SEARCH_VERSION
FROM opensearchproject/opensearch:${OPEN_SEARCH_VERSION}
# COPY --chmod=755 assets/opensearch/init.sh /usr/share/opensearch/config/
## Copy all the required resources right from the building of the image
# COPY --chown=opensearch:opensearch assets/opensearch/config/os01/opensearch.yml /usr/share/opensearch/config/
# COPY --chown=opensearch:opensearch assets/opensearch/certs/admin.pem /usr/share/opensearch/config/
# COPY --chown=opensearch:opensearch assets/opensearch/certs/root-ca.pem usr/share/opensearch/config/root-ca.pem
# COPY --chown=opensearch:opensearch assets/opensearch/certs/root-ca-key.pem usr/share/opensearch/config/root-ca-key.pem
# COPY --chown=opensearch:opensearch assets/opensearch/certs/admin.pem usr/share/opensearch/config/admin.pem
# COPY --chown=opensearch:opensearch assets/opensearch/certs/admin-key.pem usr/share/opensearch/config/admin-key.pem
# COPY --chown=opensearch:opensearch assets/opensearch/certs/os01.pem usr/share/opensearch/config/os01.pem
# COPY --chown=opensearch:opensearch assets/opensearch/certs/os01-key.pem usr/share/opensearch/config/os01-key.pem
# COPY --chown=opensearch:opensearch assets/opensearch/config/os01/opensearch-security/config.yml usr/share/opensearch/config/opensearch-security/config.yml
# COPY --chown=opensearch:opensearch assets/opensearch/config/os01/opensearch-security/internal_users.yml usr/share/opensearch/config/opensearch-security/internal_users.yml
# COPY --chown=opensearch:opensearch assets/opensearch/config/os01/opensearch-security/roles_mapping.yml usr/share/opensearch/config/opensearch-security/roles.yml
# COPY --chown=opensearch:opensearch assets/opensearch/config/os01/opensearch-security/roles_mapping.yml usr/share/opensearch/config/opensearch-security/roles_mapping.yml
# COPY --chown=opensearch:opensearch assets/opensearch/config/os01/opensearch-security/nodes_dn.yml usr/share/opensearch/config/opensearch-security/nodes_dn.yml
USER root
RUN dnf -y install iputils net-tools curl procps --skip-broken

# Install analysis-icu plugin (required by Koha for icu_folding, icu_tokenizer, icu_normalizer)
USER opensearch
RUN /usr/share/opensearch/bin/opensearch-plugin install --batch analysis-icu
USER root
USER 1000