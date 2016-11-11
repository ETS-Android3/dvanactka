//
//  RadniceAktualCtl.swift
//  Dvanactka
//
//  Created by Jan Adamec on 30.10.16.
//  Copyright © 2016 Jan Adamec. All rights reserved.
//

import UIKit
import MapKit
import EventKit
import EventKitUI

class NewsCell: UITableViewCell {
    @IBOutlet weak var m_lbTitle: UILabel!
    @IBOutlet weak var m_lbText: UILabel!
    @IBOutlet weak var m_lbDate: UILabel!
    @IBOutlet weak var m_btnWebsite: UIButton!
    @IBOutlet weak var m_btnFavorite: UIButton!
    @IBOutlet weak var m_btnAction: UIButton!
}
class EventCell: UITableViewCell {
    @IBOutlet weak var m_lbTitle: UILabel!
    @IBOutlet weak var m_lbText: UILabel!
    @IBOutlet weak var m_lbDate: UILabel!
    @IBOutlet weak var m_btnWebsite: UIButton!
    @IBOutlet weak var m_btnBuy: UIButton!
    @IBOutlet weak var m_btnAddToCalendar: UIButton!
    
}
class PlaceCell: UITableViewCell {
    @IBOutlet weak var m_lbTitle: UILabel!
    @IBOutlet weak var m_lbText: UILabel!
    @IBOutlet weak var m_imgIcon: UIImageView!
    
}

class EventsCtl: UITableViewController, CLLocationManagerDelegate, EKEventEditViewDelegate, CRxDataSourceRefreshDelegate {
    var m_aDataSource: CRxDataSource?
    var m_orderedItems = [String : [CRxEventRecord]]()  // category localName -> array of records
    var m_orderedCategories = [String]()                // sorted category local names
    var m_locManager = CLLocationManager();
    var m_coordLast = CLLocationCoordinate2D(latitude:0, longitude: 0);
    var m_bUserLocationAcquired = false;

    override func viewDidLoad() {
        super.viewDidLoad()

        let refreshCtl = UIRefreshControl();
        refreshCtl.backgroundColor = UIColor(red:131.0/255.0, green:156.0/255.0, blue:192.0/255.0, alpha:1.0);
        refreshCtl.attributedTitle = NSAttributedString(string: stringWithLastUpdateDate());
        refreshCtl.addTarget(self, action:#selector(downloadData), for:.valueChanged);
        self.refreshControl = refreshCtl;

        m_locManager.delegate = self;
        m_locManager.distanceFilter = 5;

        if let ds = m_aDataSource {
            self.title = ds.m_sTitle;
            
            if ds.m_eType == .places {
                // init location tracking
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Map", comment: ""), style: .plain, target: self, action: #selector(EventsCtl.showMap));

                self.tableView.allowsSelection = true;
                if CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
                    m_locManager.startUpdatingLocation();
                }
            } else if ds.m_eType == .news && ds.m_sId != CRxDataSourceManager.dsSavedNews {
                // link to saved news
                self.navigationItem.rightBarButtonItem = UIBarButtonItem(title: NSLocalizedString("Saved", comment: ""), style: .plain, target: self, action: #selector(EventsCtl.savedNews));
            }
            self.tableView.rowHeight = UITableViewAutomaticDimension;
            self.tableView.estimatedRowHeight = 90.0;
        }
        setRecordsDistance();
        sortRecords();
    }
    
    deinit {
        if let ds = m_aDataSource {
            ds.delegate = nil;
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated);

        guard let ds = m_aDataSource, let refreshCtl = self.refreshControl else { return }
        if ds.m_bIsBeingRefreshed {
            ds.delegate = self;
            
            // show refresh ctl, has to be when UI is visible (thus viewDidAppear)
            refreshCtl.beginRefreshing();
            //self.tableView.contentOffset = CGPoint(x:0, y:self.tableView.contentOffset.y-refreshCtl.frame.size.height);
            UIView.animate(withDuration: 0.25, delay: 0, options: .beginFromCurrentState, animations: {
                self.tableView.contentOffset = CGPoint(x:0, y:self.tableView.contentOffset.y-refreshCtl.frame.size.height);}
            );
        }
    }
    
    func sortRecords() {
        guard let ds = m_aDataSource else { return }
        m_orderedItems.removeAll();
        m_orderedCategories.removeAll();
        
        let df = DateFormatter();
        df.dateStyle = .full;
        df.timeStyle = .none;
        let today = Date();
        
        // first add objects to groups
        for rec in ds.m_arrItems {
            // favorities
            if ds.m_eType == .news {
                rec.m_bMarkFavorite = (CRxDataSourceManager.sharedInstance.findFavorite(news: rec) != nil);
                
            } else if ds.m_eType == .places {
                rec.m_bMarkFavorite = CRxDataSourceManager.sharedInstance.m_setPlacesNotified.contains(rec.m_sTitle);
            }
            // categories
            var sCatName = "";
            switch ds.m_eType {
            case .news: sCatName = "";    // one category for news
            case .places: sCatName = CRxEventRecord.categoryLocalName(category: rec.m_eCategory);
            case .events:   // use date as category
                guard let date = rec.m_aDate else {
                    continue    // remove recoords without date
                }
                if date < today {   // do not show old events
                    continue;
                }
                sCatName = df.string(from: date);
            }
            // categories
            if m_orderedItems[sCatName] == nil {
                m_orderedItems[sCatName] = [rec];   // new category
                m_orderedCategories.append(sCatName);
            }
            else {
                m_orderedItems[sCatName]?.append(rec);  // into existing
            }
        }
        if ds.m_eType == .places || ds.m_eType == .events {
            // now sort each group by distance and name
            var sortedItems = [String : [CRxEventRecord]]();
            for groupIt in m_orderedItems {
                if ds.m_eType == .places {
                    sortedItems[groupIt.key] = groupIt.value.sorted(by: {($0.m_bMarkFavorite && !$1.m_bMarkFavorite) || ($0.m_bMarkFavorite == $1.m_bMarkFavorite && $0.m_distFromUser < $1.m_distFromUser) });
                }
                else if (ds.m_eType == .events) {
                    sortedItems[groupIt.key] = groupIt.value.sorted(by: {$0.m_aDate! < $1.m_aDate! });
                }
            }
            m_orderedItems = sortedItems;
        }
        
        // remember last item shown
        if ds.m_eType == .news && ds.m_sId != CRxDataSourceManager.dsSavedNews {
            if let recFirst = ds.m_arrItems.first {
                let sNewRecHash = recFirst.recordHash();
                if sNewRecHash != ds.m_sLastItemShown { // resave only when something changed
                    ds.m_sLastItemShown = sNewRecHash;
                    CRxDataSourceManager.sharedInstance.save(dataSource: ds);
                }
            }
        }
    }
    
    func setRecordsDistance() {
        guard let ds = m_aDataSource else {
            return
        }
        if !m_bUserLocationAcquired {
            return
        }
        let locUser = CLLocation(latitude: m_coordLast.latitude, longitude: m_coordLast.longitude);
        for rec in ds.m_arrItems {
            if let loc = rec.m_aLocation {
                rec.m_distFromUser = loc.distance(from: locUser);
            }
        }
    }
    
    //---------------------------------------------------------------------------
    func stringWithLastUpdateDate() -> String {
        if let ds = m_aDataSource, let date = ds.m_dateLastRefreshed {
            let sTime = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short);
            return NSLocalizedString("Last update:", comment: "") + " " + sTime;
        }
        else {
            return NSLocalizedString("Pull main table to refresh", comment:"");
        }
    }

    //---------------------------------------------------------------------------
    func downloadData() {
        if let ds = m_aDataSource {
            ds.delegate = self;
            CRxDataSourceManager.sharedInstance.refreshDataSource(id: ds.m_sId, force: true);
        }
    }
    
    //---------------------------------------------------------------------------
    func dataSourceRefreshEnded(_ error: String?) { // protocol CRxDataSourceRefreshDelegate
        if let ds = m_aDataSource {
            ds.delegate = nil;
        }
        
        if let sErrorText = error {
            if let refreshCtl = self.refreshControl {
                refreshCtl.attributedTitle = NSAttributedString(string: sErrorText);
                Timer.scheduledTimer(timeInterval: 2, target: refreshCtl, selector: #selector(UIRefreshControl.endRefreshing), userInfo: nil, repeats: false);
            }
        }
        else {
            setRecordsDistance();
            sortRecords();
            self.tableView.reloadData();
            self.refreshControl?.attributedTitle = NSAttributedString(string: stringWithLastUpdateDate());
            self.refreshControl?.endRefreshing();
        }
    }

    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return m_orderedCategories.count;
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let items = m_orderedItems[m_orderedCategories[section]] {
            return items.count;
        }
        else {
            return 0;
        }
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (m_orderedCategories.count < 2) {
            return nil
        }
        return m_orderedCategories[section];
    }
    
    func record(at indexPath:IndexPath) -> CRxEventRecord? {
        if indexPath.section >= m_orderedCategories.count {
            return nil;
        }
        if let items = m_orderedItems[m_orderedCategories[indexPath.section]] {
            return items[indexPath.row];
        }
        else {
            return nil;
        }
    }
    
    func btnTag(from indexPath:IndexPath) -> Int {
        return indexPath.section*10000 + indexPath.row;
    }
    func btnIndexPath(from tag:Int) -> IndexPath {
        return IndexPath(row: tag % 10000, section: tag / 10000);
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        guard let rec = record(at: indexPath),
            let ds = m_aDataSource
            else {return UITableViewCell();}

        var cell: UITableViewCell!;
        
        if ds.m_eType == .news {
            let cellNews = tableView.dequeueReusableCell(withIdentifier: "cellNews", for: indexPath) as! NewsCell
            // Localization
            cellNews.m_btnWebsite.setTitle(NSLocalizedString("Continue reading on website", comment: ""), for: .normal);

            cellNews.m_lbTitle.text = rec.m_sTitle;
            
            var sNewsText = "";
            if let sText = rec.m_sText {
                sNewsText = "(praha12.cz) " + sText;
            }
            cellNews.m_lbText.text = sNewsText;
            var sDateText = "";
            if let aDate = rec.m_aDate {
                let df = DateFormatter();
                df.dateStyle = .full;
                df.timeStyle = .none;
                sDateText = df.string(from: aDate);
            }
            cellNews.m_lbDate.text = sDateText
            cellNews.m_btnWebsite.isHidden = (rec.m_sInfoLink==nil);
            cellNews.m_btnAction.isHidden = (rec.m_sInfoLink==nil);
            cellNews.m_btnFavorite.setImage(UIImage(named: (rec.m_bMarkFavorite ? "goldstar25" : "goldstar25dis")), for: .normal);
            let iBtnTag = btnTag(from: indexPath);
            cellNews.m_btnWebsite.tag = iBtnTag;
            cellNews.m_btnAction.tag = iBtnTag;
            cellNews.m_btnFavorite.tag = iBtnTag;
            cell = cellNews;
        }
        else if ds.m_eType == .events {
            let cellEvent = tableView.dequeueReusableCell(withIdentifier: "cellEvent", for: indexPath) as! EventCell
            // Localization
            cellEvent.m_btnWebsite.setTitle(NSLocalizedString("Website", comment: ""), for: .normal);
            cellEvent.m_btnBuy.setTitle(NSLocalizedString("Buy", comment: ""), for: .normal);
            cellEvent.m_btnAddToCalendar.setTitle(NSLocalizedString("Add to Calendar", comment: ""), for: .normal);
            
            cellEvent.m_lbTitle.text = rec.m_sTitle;
            cellEvent.m_lbText.text = rec.m_sText ?? "";
            var sDateText = "";
            if let aDate = rec.m_aDate {
                let df = DateFormatter();
                df.dateStyle = .none;
                df.timeStyle = .short;
                sDateText = df.string(from: aDate);
                if let aDateTo = rec.m_aDateTo {
                    sDateText += "\n- " + df.string(from: aDateTo);
                }
            }
            else {
                cellEvent.m_btnAddToCalendar.isHidden = true;
            }
            cellEvent.m_lbDate.text = sDateText
            cellEvent.m_btnWebsite.isHidden = (rec.m_sInfoLink==nil);
            cellEvent.m_btnBuy.isHidden = (rec.m_sBuyLink==nil);
            
            let iBtnTag = btnTag(from: indexPath);
            cellEvent.m_btnWebsite.tag = iBtnTag;
            cellEvent.m_btnBuy.tag = iBtnTag;
            cellEvent.m_btnAddToCalendar.tag = iBtnTag;
            cell = cellEvent;
        }
        else if ds.m_eType == .places {
            let cellPlace = tableView.dequeueReusableCell(withIdentifier: "cellPlace", for: indexPath) as! PlaceCell
            cellPlace.m_lbTitle.text = rec.m_sTitle;
            var sDistance = "";
            if m_bUserLocationAcquired && rec.m_aLocation != nil {
                let nf = NumberFormatter()
                nf.minimumFractionDigits = 2;
                nf.maximumFractionDigits = 2;
                if rec.m_distFromUser > 1000 {
                    if let km = nf.string(from: NSNumber(value: rec.m_distFromUser/1000.0)) {   // using locale
                        sDistance = "\(km) km";
                    }
                }
                else {
                    sDistance = "\(Int(rec.m_distFromUser)) m";
                }
            }
            if let text = rec.m_sText {
                if !sDistance.isEmpty {
                    sDistance += " | ";
                }
                sDistance += text;
            }
            if sDistance.isEmpty {
                sDistance = "  "    // must not be empty, causes strange effects
            }
            cellPlace.m_lbText.text = sDistance;
            
            if rec.m_bMarkFavorite {
                cellPlace.m_imgIcon.image = UIImage(named: "goldstar25");
            }
            else if let category = rec.m_eCategory {
                cellPlace.m_imgIcon.image = UIImage(named: CRxEventRecord.categoryIconName(category: category));
            }
            else {
                cellPlace.m_imgIcon.image = nil;
            }
            cell = cellPlace;
        }
        else {
            cell = UITableViewCell();
        }
        
        if ds.m_eType != .places {
            cell.setNeedsUpdateConstraints();
            cell.updateConstraintsIfNeeded();
        }
        return cell;
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        
        view.tintColor = UIColor(red: 36.0/255.0, green: 40.0/255.0, blue: 121.0/255.0, alpha: 1.0);    // background
        if let header = view as? UITableViewHeaderFooterView {          // text
            header.textLabel?.textColor = .white;
            //header.contentView.backgroundColor = UIColor(red: 36.0/255.0, green: 40.0/255.0, blue: 121.0/255.0, alpha: 1.0);
        }

    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let rec = record(at: indexPath) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let placeCtl = storyboard.instantiateViewController(withIdentifier: "placeDetailCtl") as! PlaceDetailCtl
            placeCtl.m_aRecord = rec;     // addRefs the object, keeps it even when it is deleted in DS during refresh
            navigationController?.pushViewController(placeCtl, animated: true);
        }
    }

    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        if let rec = record(at: indexPath) {
            rec.openInfoLink();
        }
    }
    
    @IBAction func onBtnWebsiteTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.openInfoLink();
        }
    }

    @IBAction func onBtnWebsiteNewsTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.openInfoLink();
        }
    }
    
    @IBAction func onBtnBuyTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.openBuyLink();
        }
        
    }
    
    @IBAction func onBtnActionTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            
            var items = [Any]();
            if let sText = rec.m_sText {
                items.append("\(rec.m_sTitle)\n\(sText)" as NSString);
            }
            if let sLink = rec.m_sInfoLink,
                let url = URL(string: sLink) {
                items.append(url as NSURL)
            }
            
            let activityViewController = UIActivityViewController(activityItems: items, applicationActivities: nil);
            present(activityViewController, animated: true, completion: nil)
        }
    }
    
    func addEventToCalendar(_ title: String, description: String?, location: String?, startDate: Date, endDate: Date) {
        let eventStore = EKEventStore()
        
        eventStore.requestAccess(to: .event, completion: { (granted, error) in
            if (granted) && (error == nil) {
                let event = EKEvent(eventStore: eventStore)
                event.title = title
                event.notes = description
                event.location = location?.replacingOccurrences(of: "\n", with: ", ")
                event.startDate = startDate
                event.endDate = endDate
                event.notes = description
                event.calendar = eventStore.defaultCalendarForNewEvents
                
                let eventController = EKEventEditViewController()
                eventController.eventStore = eventStore
                eventController.editViewDelegate = self
                eventController.event = event
                
                self.present(eventController, animated: true, completion: nil);
            } else {
                let alertController = UIAlertController(title: NSLocalizedString("Access Denied", comment:""),
                                              message: NSLocalizedString("Permission is needed to access the calendar. Go to Settings > Privacy > Calendars to allow access for this app.", comment:""), preferredStyle: .alert);
                let actionOK = UIAlertAction(title: "OK", style: .default, handler: { (result : UIAlertAction) -> Void in
                    print("OK")})
                alertController.addAction(actionOK);
                self.present(alertController, animated: true, completion: nil);
            }
        })
    }
    
    func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) {
        self.dismiss(animated: true, completion: nil);
    }
    
    @IBAction func onBtnCalendarTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            if let startDate = rec.m_aDate {
                var endDate = rec.m_aDateTo
                if endDate == nil {
                    endDate = startDate.addingTimeInterval(60*60)   // 1 hour
                }
                addEventToCalendar(rec.m_sTitle, description:nil, location:rec.m_sAddress, startDate: startDate, endDate: endDate!);
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let lastLocation = locations.last {
            m_coordLast = lastLocation.coordinate;
            m_bUserLocationAcquired = true;
            
            setRecordsDistance();
            sortRecords();
            self.tableView.reloadData();
        }
    }

    func showMap() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let mapCtl = storyboard.instantiateViewController(withIdentifier: "mapCtl") as! MapCtl
        mapCtl.m_aDataSource = m_aDataSource;
        mapCtl.m_coordLast = m_coordLast;
        navigationController?.pushViewController(mapCtl, animated: true);
    }
    
    @IBAction func onBtnNewsFavorite(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.m_bMarkFavorite = !rec.m_bMarkFavorite;
            btn.setImage(UIImage(named: (rec.m_bMarkFavorite ? "goldstar25" : "goldstar25dis")), for: .normal);
            CRxDataSourceManager.sharedInstance.setFavorite(news: rec, set: rec.m_bMarkFavorite);
        }
    }
    
    func savedNews() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let eventCtl = storyboard.instantiateViewController(withIdentifier: "eventCtl") as! EventsCtl
        eventCtl.m_aDataSource = CRxDataSourceManager.sharedInstance.m_aSavedNews;
        navigationController?.pushViewController(eventCtl, animated: true);
    }
    
}
