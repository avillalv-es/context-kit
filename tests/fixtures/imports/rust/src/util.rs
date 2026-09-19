//! Small string helpers. A leaf: it imports nothing from the crate.

/// Turn a display name into a slug.
///
/// ```
/// use appsvc::util::slugify;
/// assert_eq!(slugify("Big Name"), "big-name");
/// ```
pub fn slugify(input: &str) -> String {
    input.trim().to_lowercase().replace(' ', "-")
}

#[cfg(test)]
mod tests {
    use super::slugify;
    use crate::util::slugify as slug;

    #[test]
    fn slugs() {
        assert_eq!(slugify(" Big Name "), "big-name");
        assert_eq!(slug("A B"), "a-b");
    }
}
