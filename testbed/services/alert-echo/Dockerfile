FROM node:20-alpine
ARG VERSION
ARG GIT_SHA
ARG CODE_HASH
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY index.js ./
ENV NODE_ENV=production PORT=8080
LABEL code.hash=${CODE_HASH} git.sha=${GIT_SHA}
USER node
CMD ["node", "index.js"]
