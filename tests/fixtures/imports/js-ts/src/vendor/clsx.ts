// Basename collides with the npm package "clsx", which three other files import
// as a bare specifier. Only the relative import in src/widgets/Card.jsx points
// at this file.
export default function vendorClsx(): string {
  return "vendor";
}
