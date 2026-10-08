import RumbleServices
import SwiftUI

struct DishCardView: View {
    let dish: Dish

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
                .clipped()

            VStack(alignment: .leading, spacing: 8) {
                Text(dish.title).font(.title2.bold())
                Text(dish.summary).font(.body).foregroundStyle(.secondary)
                HStack {
                    Label("\(dish.minutes) min", systemImage: "clock")
                    Spacer()
                    if dish.canCookNow {
                        Label("You have everything", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Need \(dish.missingIngredients.count) more", systemImage: "cart")
                    }
                }
                .font(.footnote)
                if !dish.missingIngredients.isEmpty {
                    Text(dish.missingIngredients.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .shadow(radius: 8, y: 4)
        .accessibilityElement(children: .combine)
    }

    /// Photos come from a CDN URL; until then (or without one) a colour derived from the title stands in.
    @ViewBuilder
    private var photo: some View {
        if let url = dish.imageURL {
            // TODO: replace with the URLSession + on-disk image cache from the design doc.
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                fallback
            }
        } else {
            fallback
        }
    }

    private var fallback: some View {
        let hue = Double(abs(dish.id.hashValue) % 360) / 360
        return ZStack {
            LinearGradient(
                colors: [Color(hue: hue, saturation: 0.5, brightness: 0.95), Color(hue: hue, saturation: 0.7, brightness: 0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "fork.knife").font(.system(size: 64)).foregroundStyle(.white.opacity(0.8))
        }
    }
}
