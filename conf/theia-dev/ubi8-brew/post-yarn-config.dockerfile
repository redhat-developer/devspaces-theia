RUN echo "Installed npm Packages" && npm ls -g | sort | uniq && yarn global list && echo "End Of Installed npm Packages"

