// The complaint form for a stakeholder type. Logged-in people already have a
// type on their profile, so they go straight to their own form; only people
// with no type yet see the "select your category" page.
const FORM_BY_TYPE = {
  Internal: "/lodge-internal",
  Contract: "/lodge-contract",
  External: "/lodge-external",
};

export function lodgeRouteFor(userType, search = "") {
  const form = FORM_BY_TYPE[userType];
  return form ? `${form}${search}` : `/lodge-selection${search}`;
}
