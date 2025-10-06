import SwiftUI
import CoreData

struct StockView: View {
    @Environment(\.managedObjectContext) private var managedObjectContext
    @FetchRequest(fetchRequest: Medicine.extractMedicines()) private var medicines: FetchedResults<Medicine>

    var body: some View {
        NavigationView {
            List {
                ForEach(medicines) { medicine in
                    StockRowView(stockRowViewModel: StockRowViewModel(context: managedObjectContext, medicine: medicine), medicine: medicine)
                }
            }
            .navigationTitle("Stocks")
        }
    }
}

struct StockView_Previews: PreviewProvider {
    static var previews: some View {
        StockView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
