//
//  RadniceAktualCtl.swift
//  Dvanactka
//
//  Created by Jan Adamec on 30.10.16.
//  Copyright © 2016 Jan Adamec. All rights reserved.
//

import UIKit
import MapKit
import MessageUI
import EventKit
import EventKitUI

protocol CRxDetailRefreshParentDelegate {
    func detailRequestsRefresh();
}

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
    @IBOutlet weak var m_lbAddress: UILabel!
    @IBOutlet weak var m_lbText: UILabel!
    @IBOutlet weak var m_lbDate: UILabel!
    @IBOutlet weak var m_btnWebsite: UIButton!
    @IBOutlet weak var m_btnBuy: UIButton!
    @IBOutlet weak var m_btnAddToCalendar: UIButton!
    @IBOutlet weak var m_stackContact: UIStackView!
    @IBOutlet weak var m_lbContact: UILabel!
    @IBOutlet weak var m_btnEmail: UIButton!
    @IBOutlet weak var m_btnPhone: UIButton!
}
class PlaceCell: UITableViewCell {
    @IBOutlet weak var m_lbTitle: UILabel!
    @IBOutlet weak var m_lbText: UILabel!
    @IBOutlet weak var m_imgIcon: UIImageView!
}

class EventsCtl: UITableViewController, CLLocationManagerDelegate, EKEventEditViewDelegate, MFMailComposeViewControllerDelegate, CRxDataSourceRefreshDelegate, CRxDetailRefreshParentDelegate, CRxFilterChangeDelegate {
    
    @IBOutlet weak var m_viewFooter: UIView!
    @IBOutlet weak var m_lbFooterText: UILabel!
    @IBOutlet weak var m_btnFooterButton: UIButton!
    
    var m_aDataSource: CRxDataSource?
    var m_sParentFilter: String?                        // show only items with this filter (for ds with filterAsParentView)
    var m_orderedItems = [String : [CRxEventRecord]]()  // category localName -> array of records
    var m_orderedCategories = [String]()                // sorted category local names
    var m_locManager = CLLocationManager();
    var m_coordLast = CLLocationCoordinate2D(latitude:0, longitude: 0);
    var m_bUserLocationAcquired = false;
    var m_footerToShow: UIView? = nil; // it's here to save the footer pointer for later, not to release it

    var m_refreshParentDelegate: CRxDetailRefreshParentDelegate?;
    
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
            if let sParentFilter = m_sParentFilter {
                self.title = sParentFilter;
            }
            else {
                self.title = ds.m_sTitle;
            }
            
            var arrBtnItems = [UIBarButtonItem]();
            if ds.m_eType == .places {
                // init location tracking
                arrBtnItems.append(UIBarButtonItem(title: NSLocalizedString("Map", comment: ""), style: .plain, target: self, action: #selector(EventsCtl.showMap)));

                self.tableView.allowsSelection = true;
                if CLLocationManager.authorizationStatus() == .authorizedWhenInUse {
                    m_locManager.startUpdatingLocation();
                }
            } else if ds.m_eType == .news && ds.m_sId != CRxDataSourceManager.dsSavedNews {
                // link to saved news
                arrBtnItems.append(UIBarButtonItem(image: UIImage(named: "star"), style: .plain, target: self, action: #selector(EventsCtl.onSavedNews)));
            }
            if ds.m_bFilterable {
                arrBtnItems.append(UIBarButtonItem(image: UIImage(named: "filter"), style: .plain, target: self, action: #selector(EventsCtl.onDefineFilter)));
            }
            /*if ds.m_sId == CRxDataSourceManager.dsSpolky {
                arrBtnItems.append(UIBarButtonItem(image: UIImage(named: "bulleted_list"), style: .plain, target: self, action: #selector(EventsCtl.onBtnList)));
            }*/
            if arrBtnItems.count > 0 {
                self.navigationItem.setRightBarButtonItems(arrBtnItems, animated: false);
            }
            self.tableView.rowHeight = UITableViewAutomaticDimension;
            self.tableView.estimatedRowHeight = 90.0;
            
            // footer
            m_footerToShow = m_viewFooter;
            if ds.m_sId == CRxDataSourceManager.dsWork {
                m_lbFooterText.text = NSLocalizedString("Add job offer:", comment: "");
                m_btnFooterButton.setTitle("KdeJePrace.cz", for: .normal);
            }
            else if ds.m_eType == .places/* && ds.m_sId != CRxDataSourceManager.dsCooltour*/ {
                m_lbFooterText.text = NSLocalizedString("Add record:", comment: "");
            }
            else {
                m_footerToShow = nil;
            }
            // footer will be added as the last section's footer, it will stay visible then
            m_viewFooter.removeFromSuperview();
            self.tableView.tableFooterView = nil;
        }
        setRecordsDistance();
        sortRecords();
        
        // Google Analytics
        if let ds = m_aDataSource,
            let tracker = GAI.sharedInstance().defaultTracker {
            if let parentFilter = m_sParentFilter {
                tracker.set(kGAIScreenName, value: "DS_" + parentFilter);
            }
            else {
                tracker.set(kGAIScreenName, value: "DS_" + ds.m_sId);
            }
            
            if let builder = GAIDictionaryBuilder.createScreenView() {
                tracker.send(builder.build() as [NSObject : AnyObject])
            }
        }
    }
    
    //--------------------------------------------------------------------------
    deinit {
        if let ds = m_aDataSource {
            ds.delegate = nil;
        }
    }
    
    //--------------------------------------------------------------------------
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
    
    //--------------------------------------------------------------------------
    func sortRecords() {
        guard let ds = m_aDataSource else { return }
        
        m_orderedItems.removeAll();
        m_orderedCategories.removeAll();
        
        let df = DateFormatter();
        df.dateStyle = .full;
        df.timeStyle = .none;
        let today = Date();
        
        var arrDateCategories = [Date]();
        
        // first add objects to groups
        for rec in ds.m_arrItems {
            // favorities
            if ds.m_eType == .news {
                rec.m_bMarkFavorite = (CRxDataSourceManager.sharedInstance.findFavorite(news: rec) != nil);
                
            } else if ds.m_eType == .places {
                rec.m_bMarkFavorite = CRxDataSourceManager.sharedInstance.m_setPlacesNotified.contains(rec.m_sTitle);
            }
            
            // filter
            if ds.m_bFilterable {
                if let setFilter = ds.m_setFilter,
                    let sFilter = rec.m_sFilter {
                    if setFilter.contains(sFilter) {
                        continue;   // skip this record
                    }
                }
            }
            if ds.m_bFilterAsParentView {
                if let sFilter = rec.m_sFilter,
                    let sParentFilter = m_sParentFilter {
                    if sFilter != sParentFilter {
                        continue;
                    }
                }
            }
            
            // categories
            var sCatName = "";
            var dateCat: Date?;
            switch ds.m_eType {
            case .news: break;    // one category for news
                
            case .places:
                if ds.m_bGroupByCategory {
                    sCatName = CRxEventRecord.categoryLocalName(category: rec.m_eCategory);
                }
                break;
                
            case .events:   // use date as category
                guard let date = rec.m_aDate else {
                    continue    // remove records without date
                }
                if date < today && rec.m_aDateTo != nil && rec.m_aDateTo! >= today &&
                    (rec.m_aDateTo!.timeIntervalSince(date) > 24*60*60) {       // more then 1 day
                    sCatName = NSLocalizedString("Multi-day events", comment: "");
                    dateCat = date;
                }
                else if date < today {   // do not show old events
                    continue;
                }
                else {
                    sCatName = df.string(from: date);
                    dateCat = date;
                }
            }
            // categories
            if m_orderedItems[sCatName] == nil {
                m_orderedItems[sCatName] = [rec];   // new category
                m_orderedCategories.append(sCatName);
                
                if dateCat != nil {
                    arrDateCategories.append(dateCat!);
                }
            }
            else {
                m_orderedItems[sCatName]?.append(rec);  // into existing
            }
        }
        
        // sort date categories and then
        if ds.m_eType == .events {
            let combined = zip(arrDateCategories, m_orderedCategories).sorted {$0.0 < $1.0}
            m_orderedCategories = combined.map {$0.1};
        }
        
        // now sort each group by distance (places) or date (events, news)
        var sortedItems = [String : [CRxEventRecord]]();
        for groupIt in m_orderedItems {
            switch ds.m_eType {
            case .news:
                sortedItems[groupIt.key] = groupIt.value.sorted(by: {$0.m_aDate! > $1.m_aDate! });
            case .events:
                sortedItems[groupIt.key] = groupIt.value.sorted(by: {$0.m_aDate! < $1.m_aDate! });
            case .places:
                sortedItems[groupIt.key] = groupIt.value.sorted(by: {($0.m_bMarkFavorite && !$1.m_bMarkFavorite) || ($0.m_bMarkFavorite == $1.m_bMarkFavorite && $0.m_distFromUser < $1.m_distFromUser) });
            }
        }
        m_orderedItems = sortedItems;
        
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
    
    //--------------------------------------------------------------------------
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
    
    //--------------------------------------------------------------------------
    func detailRequestsRefresh()
    {
        sortRecords();
        self.tableView.reloadData();
    }

    //--------------------------------------------------------------------------
    // MARK: - Table view data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return m_orderedCategories.count;
    }

    //--------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let items = m_orderedItems[m_orderedCategories[section]] {
            return items.count;
        }
        else {
            return 0;
        }
    }
    
    //--------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if (m_orderedCategories.count < 2) {
            return nil
        }
        return m_orderedCategories[section];
    }
    
    //--------------------------------------------------------------------------
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
    
    //--------------------------------------------------------------------------
    func btnTag(from indexPath:IndexPath) -> Int {
        return indexPath.section*10000 + indexPath.row;
    }
    func btnIndexPath(from tag:Int) -> IndexPath {
        return IndexPath(row: tag % 10000, section: tag / 10000);
    }

    //--------------------------------------------------------------------------
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
            
            let sText = NSMutableAttributedString(string:"");
            if let sRecFilter = rec.m_sFilter {
                let aBoldAttr = [NSFontAttributeName: UIFont.boldSystemFont(ofSize: cellNews.m_lbText.font.pointSize)];
                sText.append(NSAttributedString(string:sRecFilter, attributes: aBoldAttr));
            }
            if let sRecText = rec.m_sText, !sRecText.isEmpty {
                if sText.length > 0 {
                    sText.append(NSAttributedString(string:" - "));
                }
                sText.append(NSAttributedString(string:sRecText));
            }
            cellNews.m_lbText.attributedText = sText;
            cellNews.m_lbText.isHidden = (sText.length == 0);
 
            var sDateText = "";
            if let aDate = rec.m_aDate {
                let df = DateFormatter();
                df.timeStyle = .none;
                if let aDateTo = rec.m_aDateTo {
                    df.dateStyle = .medium;
                    sDateText += df.string(from: aDate) + " - " + df.string(from: aDateTo);
                }
                else {
                    df.dateStyle = .full;
                    sDateText = df.string(from: aDate);
                }
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
            cellEvent.m_lbContact.text = NSLocalizedString("Contact:", comment: "")
            
            cellEvent.m_lbTitle.text = rec.m_sTitle;
            cellEvent.m_lbText.text = rec.m_sText ?? "";
            cellEvent.m_lbText.isHidden = (rec.m_sText == nil);
            
            if let address = rec.m_sAddress {
                cellEvent.m_lbAddress.text = address.replacingOccurrences(of: "\n", with: ", ");
            }
            cellEvent.m_lbAddress.isHidden = (rec.m_sAddress == nil || ds.m_sId == CRxDataSourceManager.dsBiografProgram);
            
            var sDateText = "";
            if let aDate = rec.m_aDate {
                let df = DateFormatter();
                df.dateStyle = .none;
                df.timeStyle = .short;
                let calendar = Calendar.current;
                var dtc = calendar.dateComponents([.hour, .minute], from: aDate);
                if dtc.hour! == 0 && dtc.minute == 0 {
                    df.timeStyle = .none;
                }
                sDateText = df.string(from: aDate);
                if let aDateTo = rec.m_aDateTo {
                    dtc = calendar.dateComponents([.year, .month, .day], from: aDate);
                    let dayFrom = calendar.date(from: dtc);
                    dtc = calendar.dateComponents([.year, .month, .day], from: aDateTo);
                    let dayTo = calendar.date(from: dtc);
                    
                    if dayFrom != dayTo {
                        df.dateStyle = .short;
                        sDateText = df.string(from: aDate);
                    }

                    df.timeStyle = .short;
                    dtc = calendar.dateComponents([.hour, .minute], from: aDateTo);
                    if dtc.hour! == 0 && dtc.minute == 0 {
                        df.timeStyle = .none;
                    }
                    sDateText += "\n- " + df.string(from: aDateTo);
                }
            }
            cellEvent.m_lbDate.text = sDateText
            cellEvent.m_btnWebsite.isHidden = (rec.m_sInfoLink==nil);
            cellEvent.m_btnBuy.isHidden = (rec.m_sBuyLink==nil);
            cellEvent.m_btnAddToCalendar.isHidden = (rec.m_aDate==nil);
            
            cellEvent.m_stackContact.isHidden = (rec.m_sEmail == nil && rec.m_sPhoneNumber == nil);
            if !cellEvent.m_stackContact.isHidden {
                if let phone = rec.m_sPhoneNumber {
                    cellEvent.m_btnPhone.setTitle(phone, for: .normal);
                }
                cellEvent.m_btnEmail.isHidden = (rec.m_sEmail==nil);
                cellEvent.m_btnPhone.isHidden = (rec.m_sPhoneNumber==nil);
            }
            
            let iBtnTag = btnTag(from: indexPath);
            cellEvent.m_btnWebsite.tag = iBtnTag;
            cellEvent.m_btnBuy.tag = iBtnTag;
            cellEvent.m_btnAddToCalendar.tag = iBtnTag;
            cellEvent.m_btnEmail.tag = iBtnTag;
            cellEvent.m_btnPhone.tag = iBtnTag;
            cell = cellEvent;
        }
        else if ds.m_eType == .places {
            let cellPlace = tableView.dequeueReusableCell(withIdentifier: "cellPlace", for: indexPath) as! PlaceCell

            var sRecTitle = rec.m_sTitle;
            if (CRxGame.sharedInstance.playerWas(at: rec)) {
                sRecTitle += " ✓";
            }

            var bInFuture = false;
            if let date = rec.m_aDate {
                bInFuture = (date > Date());
            }
            cellPlace.m_lbTitle.textColor = UIColor(white: bInFuture ? 0.5 : 0.0, alpha: 1.0);
            
            var bObsolete = false;   // strike-out obsolete accidents
            if let dateTo = rec.m_aDateTo {
                bObsolete = (dateTo < Date());
            }
            let aTitleAttr = (bObsolete ? [NSStrikethroughStyleAttributeName: 2] : nil);
            cellPlace.m_lbTitle.attributedText = NSAttributedString(string: sRecTitle, attributes: aTitleAttr);
            
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
            var sSubtitle = "";
            if let sNextEvent = rec.nextEventOccurenceString() {
                sSubtitle = sNextEvent;
            }
            else if let sTodayHours = rec.todayOpeningHoursString() {
                sSubtitle = sTodayHours;
            }
            /*else if let cat = rec.m_eCategory {
                sSubtitle = CRxEventRecord.categoryLocalName(category: cat);
            }*/
            else if let text = rec.m_sText {
                sSubtitle = text;
            }
            if !sSubtitle.isEmpty {
                if !sDistance.isEmpty {
                    sDistance += " | ";
                }
                sDistance += sSubtitle;
            }
            if sDistance.isEmpty {
                sDistance = "  ";    // must not be empty, causes strange effects
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
            cellPlace.m_imgIcon.isHidden = (cellPlace.m_imgIcon.image == nil);
            cell = cellPlace;
        }
        else {
            cell = UITableViewCell();
        }
        
        cell.setNeedsUpdateConstraints();
        cell.updateConstraintsIfNeeded();
        return cell;
    }
    
    //--------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        
        view.tintColor = UIColor(red: 74.0/255.0, green: 125.0/255.0, blue: 185.0/255.0, alpha: 1.0);    // background
        if let header = view as? UITableViewHeaderFooterView {          // text
            header.textLabel?.textColor = .white;
            //header.contentView.backgroundColor = UIColor(red: 36.0/255.0, green: 40.0/255.0, blue: 121.0/255.0, alpha: 1.0);
        }
    }
    
    //--------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section < m_orderedCategories.count-1 || m_footerToShow == nil {
            return nil;
        }
        // only under the last section
        return "text";
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        if section < m_orderedCategories.count-1 || m_footerToShow == nil {
            return 0;
        }
        return m_footerToShow!.bounds.height;
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        if section < m_orderedCategories.count-1 || m_footerToShow == nil {
            return nil;
        }
        return m_footerToShow;
    }
    
    //--------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let rec = record(at: indexPath) {
            let storyboard = UIStoryboard(name: "Main", bundle: nil)
            let placeCtl = storyboard.instantiateViewController(withIdentifier: "placeDetailCtl") as! PlaceDetailCtl
            placeCtl.m_aRecord = rec;     // addRefs the object, keeps it even when it is deleted in DS during refresh
            placeCtl.m_refreshParentDelegate = self;
            navigationController?.pushViewController(placeCtl, animated: true);
        }
    }

    //--------------------------------------------------------------------------
    override func tableView(_ tableView: UITableView, accessoryButtonTappedForRowWith indexPath: IndexPath) {
        if let rec = record(at: indexPath) {
            rec.openInfoLink();
        }
    }
    
    //--------------------------------------------------------------------------
    @IBAction func onBtnWebsiteTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.openInfoLink();
        }
    }

    //--------------------------------------------------------------------------
    @IBAction func onBtnWebsiteNewsTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.openInfoLink();
        }
    }
    
    //--------------------------------------------------------------------------
    @IBAction func onBtnBuyTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.openBuyLink();
            
            // Google Analytics
            if let tracker = GAI.sharedInstance().defaultTracker,
                let builder = GAIDictionaryBuilder.createEvent(withCategory: "Buy", action: "Buy", label: title ?? "", value: 1) {
                tracker.send(builder.build() as [NSObject : AnyObject])
            }
        }
    }
    
    //--------------------------------------------------------------------------
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
    
    //--------------------------------------------------------------------------
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
    
    //--------------------------------------------------------------------------
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

    //--------------------------------------------------------------------------
    @IBAction func onBtnEmailTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)),
            let email = rec.m_sEmail {
            
            let mailer = MFMailComposeViewController();
            if mailer == nil { return; }
            mailer.mailComposeDelegate = self;
            
            mailer.setToRecipients(["\(email)"]);
            var sSubject = "Zájem o " + rec.m_sTitle;
            if let date = rec.m_aDate {
                let df = DateFormatter();
                df.dateStyle = .short;
                df.timeStyle = .short;
                sSubject += " @ " + df.string(from: date);
            }
            mailer.setSubject(sSubject);
            
            mailer.modalPresentationStyle = .formSheet;
            present(mailer, animated: true, completion: nil);
        }
    }

    //--------------------------------------------------------------------------
    @IBAction func onBtnPhoneTouched(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)),
            let phone = rec.m_sPhoneNumber {
            
            let cleanedNumber = phone.replacingOccurrences(of: " ", with: "")
            
            if let url = URL(string: "telprompt://\(cleanedNumber)") {
                UIApplication.shared.openURL(url);
            }
        }
    }
    
    //--------------------------------------------------------------------------
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let lastLocation = locations.last {
            m_coordLast = lastLocation.coordinate;
            m_bUserLocationAcquired = true;
            
            setRecordsDistance();
            sortRecords();
            self.tableView.reloadData();
        }
    }

    //--------------------------------------------------------------------------
    func showMap() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let mapCtl = storyboard.instantiateViewController(withIdentifier: "mapCtl") as! MapCtl
        mapCtl.m_aDataSource = m_aDataSource;
        mapCtl.m_sParentFilter = m_sParentFilter;
        mapCtl.m_coordLast = m_coordLast;
        navigationController?.pushViewController(mapCtl, animated: true);
    }
    
    //--------------------------------------------------------------------------
    @IBAction func onBtnNewsFavorite(_ sender: Any) {
        if let btn = sender as? UIButton,
            let rec = record(at: btnIndexPath(from: btn.tag)) {
            rec.m_bMarkFavorite = !rec.m_bMarkFavorite;
            btn.setImage(UIImage(named: (rec.m_bMarkFavorite ? "goldstar25" : "goldstar25dis")), for: .normal);
            CRxDataSourceManager.sharedInstance.setFavorite(news: rec, set: rec.m_bMarkFavorite);
            
            if let ds = m_aDataSource {
                if ds.m_sId == CRxDataSourceManager.dsSavedNews {
                    m_refreshParentDelegate?.detailRequestsRefresh();
                }
            }
        }
    }
    
    //--------------------------------------------------------------------------
    func onSavedNews() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let eventCtl = storyboard.instantiateViewController(withIdentifier: "eventCtl") as! EventsCtl
        eventCtl.m_aDataSource = CRxDataSourceManager.sharedInstance.m_aSavedNews;
        eventCtl.m_refreshParentDelegate = self;
        navigationController?.pushViewController(eventCtl, animated: true);
    }

    //--------------------------------------------------------------------------
    func onBtnList() {
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let eventCtl = storyboard.instantiateViewController(withIdentifier: "eventCtl") as! EventsCtl
        eventCtl.m_aDataSource = CRxDataSourceManager.sharedInstance.m_dictDataSources[CRxDataSourceManager.dsSpolkyList];
        navigationController?.pushViewController(eventCtl, animated: true);
    }
    
    //--------------------------------------------------------------------------
    func onDefineFilter() {
        guard let ds = m_aDataSource else { return }
        
        // get the list of filter items
        var arrFilter = [String]();
        for rec in ds.m_arrItems {
            if let sFilter = rec.m_sFilter {
                if !arrFilter.contains(sFilter) {
                    arrFilter.append(sFilter);
                }
            }
        }
        
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        let filterCtl = storyboard.instantiateViewController(withIdentifier: "filterCtl") as! FilterCtl
        filterCtl.m_delegate = self;
        filterCtl.m_arrFilter = arrFilter.sorted();
        if let setOut = ds.m_setFilter {
            filterCtl.m_setOut = setOut;
        }
        navigationController?.pushViewController(filterCtl, animated: true);
    }
    
    //--------------------------------------------------------------------------
    func filterChanged(setOut: Set<String>) {
        guard let ds = m_aDataSource else { return }
        ds.m_setFilter = setOut;
        CRxDataSourceManager.sharedInstance.save(dataSource: ds);
        sortRecords();
        self.tableView.reloadData();
    }

    //--------------------------------------------------------------------------
    @IBAction func onBtnFooterTouched(_ sender: Any) {
        guard let ds = m_aDataSource else { return }
        if ds.m_sId == CRxDataSourceManager.dsWork {
            if let url = URL(string: "https://www.kdejeprace.cz/pridat?utm_source=dvanactka.info&utm_medium=app") {
                UIApplication.shared.openURL(url);
            }
        }
        else if MFMailComposeViewController.canSendMail() {
            let mailer = MFMailComposeViewController();
            if mailer == nil { return; }
            mailer.mailComposeDelegate = self;
            
            mailer.setToRecipients(["info@dvanactka.info"]);
            mailer.setSubject("P12app - přidat záznam");
            var sTitle = ds.m_sTitle;
            if let sParentFilter = m_sParentFilter {
                sTitle = sParentFilter;
            }
            mailer.setMessageBody("Data Source: \(sTitle)\n", isHTML: false);
            mailer.modalPresentationStyle = .formSheet;
            present(mailer, animated: true, completion: nil);
        }
    }

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        controller.dismiss(animated: true, completion: nil);
    }
}
