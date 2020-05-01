RUN echo "Installed npm Packages" && npm ls -g | sort | uniq || true
RUN yarn global list || true
RUN echo "End Of Installed npm Packages"
