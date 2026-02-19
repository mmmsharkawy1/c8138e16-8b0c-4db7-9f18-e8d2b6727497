/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["@tager/shared"],
  output: "standalone",
};

export default nextConfig;
