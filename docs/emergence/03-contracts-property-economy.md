# Contracts, Property, Debt, Production, and Economic Networks

## Purpose

Create a lightweight physical economy capable of generating trade, specialization, wealth inequality, debt, business formation, supply shocks, and settlement growth. Model meaningful flows rather than every transaction.

## Property

Property is an ownership relationship over land, buildings, workshops, livestock, tools, stored goods, businesses, vehicles, and later knowledge assets. Owners may be individuals, households, institutions, or governments.

## Production

Production transforms inputs into outputs:

```text
grain → flour → bread
ore → metal → tools
wood → charcoal → steel
hide → leather → armor
```

Recipes declare inputs, outputs, labor, skill, time, infrastructure, waste, and quality modifiers.

## Quality

Quality derives from material properties, tools, worker skill, technique, environment, recipe, and defects. Avoid static item statistics when the material/crafting substrate can determine the result.

## Contracts

```text
Contract {
  parties[], obligations[], consideration[], deadline, enforcement, status
}
```

Initial types: employment, supply, construction, loan, rent, protection, transport, and trade. Lifecycle: proposed → accepted → active → fulfilled; failure can be renegotiated, defaulted, breached, cancelled, or enforced. Failures emit history events and alter relationships/reputation.

## Debt and credit

Debt tracks principal, repayment schedule, collateral, creditor, debtor, due date, and status. Failure may cause property sale, labor, refinancing, renegotiation, default, migration, insolvency, or institutional assistance. Creditworthiness derives from reputation, assets, income, contract history, relationships, and institutional affiliation.

Banks should emerge later from repeated lending rather than being a prerequisite.

## Markets

Markets are local buyer/seller matching systems. Prices respond to supply, demand, stockpiles, transport cost, risk, perishability, and market access. Do not use one global price.

## Trade routes

Repeated profitable movement creates routes with endpoints, traffic, value, travel time, risk, infrastructure, and dependencies. Routes can produce trails, roads, bridges, inns, caravan stations, and settlements.

## Economic shocks

Important shocks propagate causally:

```text
mine collapse → iron shortage → tool prices rise → agricultural output falls → food prices rise → migration
```

## Businesses

Businesses own or lease production assets, hire workers, acquire inputs, sell outputs, hold contracts, and manage finances. They can fail.

## Economic institutions

Repeated businesses can produce guilds, cooperatives, merchant houses, banks, cartels, and trade associations. These must emerge from actual coordination.

## Taxation

Later governments can tax property, trade, production, transactions, or households. Tax changes can cause evasion, migration, political opposition, and black markets.

## Invariants

1. Goods have provenance.
2. Important scarcity has a physical/economic cause.
3. Trade requires transport or explicit abstraction.
4. Money does not create physical goods.
5. Economic state is locally explainable.
6. Businesses and contracts can fail.
7. Markets can collapse.
